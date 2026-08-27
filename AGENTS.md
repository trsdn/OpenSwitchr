# AGENTS.md

Guidance for AI coding agents working in this repository.

## Build & install

```bash
# Compile check
swift build -c release

# Build, bundle, and sign (creates .build/release/OpenSwitchr.app)
bash scripts/build-app.sh

# Install and run
cp -R .build/release/OpenSwitchr.app /Applications/
open /Applications/OpenSwitchr.app

# Logic tests (pure logic only — no AX, no capture, no UI)
swift test

# Everything tests cannot reach: real AX linking rates and capture timings.
# Run from a terminal that holds the Accessibility permission.
swift run openswitchr-diag --bench --capture

# End-to-end check against the *installed, running* app: synthetic hotkey,
# overlay latency, real focus change, and two Dock hovers on the same icon.
swift run openswitchr-diag --probe-app
```

There is no Xcode project. Everything goes through SwiftPM; the app bundle is
assembled manually in `scripts/build-app.sh`.

## Releases go through the broker

Distributable builds come from `trsdn/macos-notarization-broker`. Apple
credentials must never be added to this repository, and no workflow here may
use a secret, an environment, or write permissions.

The broker assembles the app bundle itself with its `openswitchr-swiftpm`
adapter, so `scripts/build-app.sh` is **not** the definition of the release
bundle — it is a local convenience that has to stay consistent with the
broker profile. Changing the bundle identifier, executable name, layout,
architecture, entitlements, or minimum macOS version requires a reviewed pull
request against the broker's `profiles/apps.json` first; otherwise preflight
rejects the release. See `RELEASE_CHECKLIST.md`.

## Architecture

OpenSwitchr is a `LSUIElement` menu bar app targeting macOS 15+. Two frontends
sit on one shared foundation, which is the entire point of the project: the
window index, the event bus, the thumbnail cache, and the window actions exist
**once**.

```
Sources/
├── OpenSwitchrCore/   Shared foundation. No UI, no frontend assumptions.
├── OpenSwitchrUI/     SwiftUI views + non-activating panel infrastructure.
├── OpenSwitchr/       App wiring: menu bar, hotkey tap, controllers, settings.
├── openswitchr-diag/  Command-line harness for the parts only real windows can judge.
└── openswitchr-icon/  Renders Resources/AppIcon.icns from OpenSwitchrUI's WindowMark.
```

**Core types:**

- `AXBridge` — the only place with raw AXUIElement C API. Typed accessors,
  actions, and observer lifecycle.
- `CGWindowSnapshot` — reads `CGWindowListCopyWindowInfo` for z-order and
  `CGWindowID`s, which ScreenCaptureKit needs.
- `WindowIndex` — `@MainActor @Observable` single source of truth. Merges AX
  windows with the CoreGraphics snapshot and keeps MRU order.
- `WindowEventBus` — AXObservers per app plus `NSWorkspace` notifications.
  Event-driven, coalesced. **Never poll.**
- `ThumbnailStore` — `actor`. ScreenCaptureKit captures behind an LRU cache
  with a hard byte budget.
- `WindowActions` — focus, minimize, restore, close.
- `WindowMatcher` — pure filter logic for the live query. Unit tested.

## Non-negotiable design constraints

- **No polling.** Idle CPU must stay near zero. Everything is driven by AX
  notifications, `NSWorkspace` notifications, or the event tap. The only mouse
  monitor allowed is the short-lived one that runs while a Dock preview panel
  is already open. The single sanctioned timer waits for a TCC grant, which the
  system announces through no other mechanism; it runs only while a grant is
  actually pending and stops as soon as it arrives.
- **Do no work nobody can see.** Being event-driven is not enough: other
  applications decide the event rate, and one window retitling itself fifteen
  times a second cost 3–7 % idle CPU by rebuilding an index no one was reading.
  Events mark the index stale; the rebuild happens on the path that puts a
  frontend on screen, where it hides behind the window being drawn.
- **Current Space only.** Windows on other Spaces are deliberately out of
  scope, because reaching them requires private SkyLight APIs. Rebuild the
  index on `activeSpaceDidChangeNotification`.
- **No private APIs.** Notably `_AXUIElementGetWindow` is off limits; AX
  windows are matched to `CGWindowID`s heuristically in `CGWindowSnapshot`.
- **Batch accessibility reads.** Every read is a synchronous message to another
  process, so cost tracks round trips, not data. Use `AXBridge.values(_:_:)` to
  fetch several attributes at once, and query different apps in parallel. Doing
  it naively costs 5x.
- **Never block the UI on a capture.** Tiles render immediately with icon and
  title; thumbnails stream in afterwards.
- **The event tap owns its own run loop thread.** On the main run loop its
  callback queues behind SwiftUI and index work, and the system disables a tap
  whose callback is late — which killed the hotkey in the field. The callback
  therefore reads a locked snapshot and must never touch main-actor state;
  `MainActor.assumeIsolated` there would be a crash, not a shortcut.
- **Keep the event tap callback trivial.** State transition only — no capture,
  no layout, no allocation-heavy work. A slow callback gets the tap disabled by
  the system.
- **Startup belongs to the app lifecycle, not to a view.** A `.menu`-style
  `MenuBarExtra` builds its content lazily when the user opens the menu, so
  anything started from that content never runs for a user who just launches
  the app and presses the hotkey. `AppDelegate` owns `AppModel` and starts it in
  `applicationDidFinishLaunching`. This shipped broken once and no test caught
  it, because every test exercised the core directly.
- **No AppKit controls inside the panels.** Both frontends render into an
  `OverlayPanel`, whose `canBecomeKey` is `false` by design — showing a preview
  must never deactivate the app the user is in. A control in a window that can
  never become key may swallow the click that would otherwise activate it, so a
  SwiftUI `Button` there is a coin flip. Every interactive element in a tile
  goes through `.onTapGesture`, which is the mechanism these panels are known to
  deliver. Nested tap gestures resolve innermost-first, so a control inside a
  tile does not also trigger the tile.
- **Interactive tiles need a real click to be believed.** Unit tests do not
  render, `openswitchr-diag` does not click controls, and the panels expose no
  content window to `computer-use`. A new control in a tile is unverified until
  a human clicks it. Say so rather than implying it was tested.
- **Settings must take effect without a relaunch.** A control that only writes a
  preference looks finished while doing nothing: `tileWidth` reached both
  frontends for weeks yet changed nothing visible, because the thumbnail cache
  never re-captured at the new size. Anything that changes capture size or
  staleness has to invalidate the cache from `applyPreferences()`.
- **A default belongs in exactly one place.** Three separate `.option` literals
  and two independent thumbnail age limits (8 s against 5 s) have each been
  found drifting apart here. Derive the second one from the first instead of
  writing a comment claiming they match.
- **Signing identity must stay stable.** TCC permissions are tied to the code
  signature; `build-app.sh` aborts on an ad-hoc signature on purpose. Its
  identity lookup must also return exactly one fingerprint: awk's `exit` runs
  the `END` block, and a keychain holding both an Apple Development and a
  Developer ID certificate once produced two, which `codesign` read as a single
  unknown identity.
- **Opening a window does not activate an `LSUIElement` app.** `SettingsLink`
  put the Settings window on screen *behind* whatever the user was looking at,
  because nothing brought OpenSwitchr forward. The menu item drives
  `openSettings()` explicitly so `NSApp.activate()` can run alongside it. Verify
  by z-order, not by eye: a window that is on screen is not necessarily in
  front.
- **The mark is drawn once, in two weights.** `WindowMark` owns the geometry for
  both the app icon and the menu bar glyph, because two drawings of the same
  logo drift. Solid art carries a 1024 pt icon and collapses into a blob at
  15 pt, so the menu bar takes the outlined style — the same split Apple ships
  as `macwindow` against `macwindow.fill`. Interior detail is punched out with
  `destinationOut` rather than painted lighter, because the mark is white on a
  blue plate in one place and a tinted template in the other, and "lighter"
  points opposite ways on those two while "less opaque" points the same way.
- **`NSBitmapImageRep.draw(in:)` discards the alpha channel.** It painted the
  mark's whole bounding box opaque, turning two overlapping windows into one
  filled rectangle, while `colorAt` proved the bitmap itself was correct. Wrap
  the rep in an `NSImage` and draw that.
- **Nothing that shows tiles may rely on `onAppear` to fetch them.** Both
  panels are only ordered out, never torn down, so their SwiftUI tree survives
  and a tile keeps its identity: `onAppear` fires once per window for the
  lifetime of the app. While that was the only thing requesting a capture,
  every path that dropped an image was permanent — `clear()` on a Space change
  dropped all of them — and previews thinned out over a session until only icon
  tiles were left. Whoever shows a set of tiles calls
  `ThumbnailProvider.prefetch` on the path that shows them, and not from a
  `render()` that also runs on hover.
- **The provider must not answer cache questions the store owns.** Skipping the
  store because an image was already loaded made every loaded preview immortal
  and turned the refresh-rate setting into a no-op — the age limit lives in
  `ThumbnailStore`, so the request has to reach it. This is the same trap as
  the tile-size one below, in the other direction.
- **A pid does not say which window was focused.** `windows` is sorted
  most-recently-used first, so "the first window of this pid" is always the
  window that was *already* on top: promoting it is a no-op that freezes the
  order. `kAXFocusedWindowChangedNotification` carries the newly focused window
  as its own element — verified against Safari with three windows — so match on
  that and keep the pid only as a fallback for apps that expose nothing usable.
  The same callback must take the pid from the element rather than from
  `NSWorkspace.frontmostApplication`, or a focus change in a background app is
  charged to whichever app happens to be in front.
- **A minimized window reports the subrole `AXDialog`.** Not
  `AXStandardWindow`, which is what the same window reported a second earlier;
  role, title, position, and size are all unchanged. Filtering on subrole alone
  hid every window the moment it reached the Dock. Anything that narrows the
  window set has to ask what it does to a minimized window, and the answer is
  only ever found by minimizing a real one — no unit test sees this, because the
  value comes from another process.

## Verifying the app, not just the core

The tests and `openswitchr-diag` both drive the core directly, so they cannot
tell you whether the *app* works. Three failures hid behind green tests: the app
never started, settings could not be changed, and hovering the same Dock icon
twice worked only the first time. Verify end to end with `openswitchr-diag
--probe-app`, which drives the installed bundle with synthetic events and
watches the window server:

- Post the configured modifier plus `Tab` with `CGEvent`, then poll
  `CGWindowListCopyWindowInfo` for a window owned by `OpenSwitchr` *on a layer
  above zero* to time how long the overlay takes to appear. Without the layer
  filter the Settings window counts as an overlay and a dead hotkey measures as
  a pass.
- Move the pointer onto a Dock icon (its frame comes from the Dock's own
  accessibility tree) and look for the preview panel the same way.
- Measure panels against a baseline of window IDs, never "is any panel open".
  Both frontends put a floating panel on screen, so a Dock preview left open by
  a pointer resting on the Dock stands in for the switcher overlay and reports
  a fast, entirely meaningless success. Park the pointer away from the Dock
  before measuring the switcher.
- Keep every fallback in the probe identical to the app's. The probe reads
  `holdModifier` from `UserDefaults` and has to fall back the way
  `PreferencesStore` registers it. When the two drifted apart, the probe pressed
  a different key than the app listened for on a fresh install, which reads as
  an app failure that does not exist.
- Watch behaviour with
  `log stream --predicate 'subsystem == "com.openswitchr.app"' --level debug`.

Repeat every gesture at least twice. Both hover bugs were invisible on a first
attempt and only appeared on the second, because the failure was stale state
left behind by the first.

Two traps when measuring: `NSWorkspace.frontmostApplication` is updated by
notifications and stays stale in a short-lived probe with no run loop, so read
the window server's z-order instead; and `ps %cpu` is an average over process
lifetime, so use interval samples for idle CPU. Also discard the first
measurement after a launch — the first overlay costs ~180 ms against ~25 ms
warm. To check a *registered* default rather than whatever is stored, delete the
key with `defaults delete com.openswitchr.app <key>` first; a value left over
from earlier testing will happily mask a wrong default.

**Suspect the measurement before the code.** Two of the longest detours in this
project were caused by a broken instrument, not a broken feature. The hypothesis
that accessibility window order tracks z-order measured "0 agree, 2 disagree"
and was nearly discarded — after the z-order itself was fixed the same test read
"4 agree, 0 disagree", and it was the only signal capable of telling four
identical windows apart. In the same investigation all four candidate orderings
inside `WindowActions.focus()` measured exactly 50 %, which looks like a race and
was in fact the same corrupt z-order being used to decide who was in front;
`focus()` was correct all along. A suspiciously round number, or an outcome that
does not change no matter what you vary, is evidence about the ruler.

## Two window-server facts that are easy to get wrong

`CGWindowListCopyWindowInfo` documents front-to-back ordering **only** for
`.optionOnScreenOnly`. The `.optionAll` listing appends off-screen and
other-Space windows in an order of its own, so an index into it is not a z-order.
This was measured: two adjacent TextEdit windows landed at 15 and 603 of 704 in
`.optionAll` and at 145 and 146 on screen. Take ranks from the on-screen listing
and sort off-screen windows behind them.

Swift's `sort` is **not stable**. Anywhere a tie is possible — and windows of one
application routinely share a frame and a title — the comparison has to be total,
or the result changes between runs for no visible reason. `AXWindowLinker` sorts
by score, then depth correspondence, then both input indices, so nothing is left
to chance.

## Concurrency

Swift 6 strict concurrency is on. `WindowIndex`, controllers, and all UI are
`@MainActor`. `ThumbnailStore` is an `actor`. AX and event tap callbacks are C
callbacks without Sendable guarantees, so they hop to the main actor
immediately and are confined to `AXBridge` / `HotkeyMonitor`.

## The name

"OpenSwitchr" is "Open Switcher" without the *e*. The vowel is dropped
deliberately: plain "OpenSwitch" belongs to the Linux Foundation's OpenSwitch
(OPX) network operating system, so it must not reappear in the bundle
identifier, the product name, or anything published. Use
`bash scripts/rename-product.sh <NewName>` for any further rename rather than
editing names by hand.

## Preferences

`UserDefaults` via `PreferencesStore`. No separate plist.

## Repository quality standard

Assessed against the [`trsdn/.github`](https://github.com/trsdn/.github)
Repository Quality Standard, version 1.3.3, on 2026-08-26. State: **Needs
work** — high-priority gaps exist, but the repository is usable.

The standard keeps its result in `.github/conformance.yml` and its narrative in
`docs/self-assessment.md`. This repository has neither, which is `B11` failing;
until they exist, this section is the record. Every line below is evidence from
the GitHub API, a workflow run, or a file in the tree — nothing is assumed.

### The finding that outranks the rest

`main` holds two files: `README.md` and `.gitignore`. Everything this document
describes — the sources, the tests, the CI workflows, `LICENSE`, this file —
lives in an unmerged branch.

Most of the standard reads the default branch or the repository settings, so a
stub default branch fails criteria the work already satisfies. GitHub reports
`license: null` for a public repository, which is the "ambiguous public
licensing" case the standard names as high-priority, and it is why `B03` and
`P01` fail despite `LICENSE` existing three commits away. Merging is the single
change that moves the most criteria.

### Profiles

| Profile | Applies | Why |
| --- | --- | --- |
| Baseline | Yes | Always |
| Public | Yes | Public visibility |
| Software | Yes | Ships a Swift package and an app bundle |
| Product Identity | Yes | Builds a signed `.app` a user installs |
| Package And Release | Yes | Releases are intended, via the notarization broker |
| Agent Readiness | Yes | This file exists and agents work here |
| Language, Accessibility, Privacy | Yes | A shipping user interface |
| Deployable | No | Nothing is deployed to any environment |
| Documentation | No | The product is software; docs support it |
| Archived | No | Actively developed |

### Gaps

| ID | Result | Observed |
| --- | --- | --- |
| `B03`, `P01` | fail | No licence on the default branch. `LICENSE` is only in the unmerged branch, so GitHub detects none. |
| `B06`, `S09` | fail | `main` is unprotected: the API answers `Branch not protected`, there are no rulesets, and CI is not a required check. |
| `B11` | fail | No `.github/conformance.yml`. |
| `B12`, `P07` | fail | No topics at all, so the `trsdn-standard` set does not include this repository. No homepage. |
| `P03` | partial | `SECURITY.md` is inherited from `trsdn/.github`, but private vulnerability reporting is disabled (`{"enabled": false}`). |
| `P04` | partial | The pull-request template is inherited; the community profile reports `issue_template: null`, so the issue forms are not applied. |
| `P08`, `P09` | fail | No status badges and no repository activity card in the README. |
| `S03` | partial | Warnings are errors in CI, which is real static analysis, but no formatter or linter is configured. |
| `S04` | partial | One job on `macos-latest`. The label is unpinned, so the macOS version under test moves without a commit while the README promises macOS 15+. |
| `S05` | partial | `secret-scan.yml` runs on every pull request and passes, but GitHub secret scanning and push protection are both disabled. |
| `S08` | fail | No `dependabot.yml` and Dependabot security updates disabled. The Swift package has no dependencies, but the workflows pin `actions/checkout@v4`, which does age. |
| `I02`, `I03` | fail | The bundle carries no repository URL, no issue tracker URL, no licence identifier, and no copyright holder. `LICENSE` is not copied into the app. |
| `I04` | partial | The About tab shows the version and links to the repository; it does not link an issue tracker. |
| `I06` | fail | `CFBundleVersion` and `CFBundleShortVersionString` are typed into `Info.plist` by hand. Nothing derives them from a tag. |
| `G03` | fail | Nothing here names forbidden or high-risk operations: history rewriting, force pushes, secret handling, releases, tag moves, repository settings. |
| `G05` | partial | Validation is several commands. The standard asks for one that an agent can run before proposing a change. |
| `G06` | fail | No path is marked as generated. `Resources/AppIcon.icns` is produced by `openswitchr-icon` and rewritten by `build-app.sh` on every build, and nothing says so. There is no `.gitattributes`. |
| `G07` | partial | Agent commits carry `Co-authored-by` trailers, but no review expectation is written down. |
| `G08` | fail | No `.github/github-app.yml`. |
| `L01`, `L03` | partial / fail | Every surface is English; nothing declares English as the primary language, and localization support is never stated as English-only. |
| `X01` | partial | The switcher is fully keyboard-driven. Dock hover previews are reachable only by pointer, which is inherent to hovering a Dock icon but is not written down anywhere. |
| `X03` | partial | Meaning never rests on colour alone — the quit control is red *and* a distinct glyph in the opposite corner — but behaviour under platform text-size settings is unverified. |
| `X05` | fail | Known accessibility limits are not stated. |
| `Y01`, `Y04` | fail | The README never says the app collects nothing and transmits nothing, and never says preferences live in `UserDefaults` under `com.openswitchr.app`. The explicit "none" case still has to be written. |
| `Y02` | partial | The app opens no outbound connection. Nothing documents that. |
| `R03`, `R05` | fail | No release workflow, no release, no smoke test of a built artifact in a clean environment. |
| `B04` | partial | `.gitignore` covers build output, `dist/`, and `.release.env`; the generated `AppIcon.icns` is tracked without being marked. |
| `B09`, `B10` | partial | Visibility and archive state are intentional; there is no `CODEOWNERS`, and the README states "Early" without naming an owner or a maintenance commitment. |
| `P05`, `P06` | partial | The README covers install, build, and compatibility, but not configuration, security, or support. The community profile sits at 85 %. |
| `S02` | partial | 42 tests, all pure logic. Everything touching accessibility or the window server is covered only by `openswitchr-diag`, which is manual and absent from CI — as the section above already admits. |
| `T02` | partial | Nothing validates the markdown. Against the standard's own `.markdownlint.jsonc` this repository reports 26 issues: 24 table-separator spacings, one fenced block without a language, and one duplicate `### Added` heading in `CHANGELOG.md`. All trivial, none currently visible to anyone. |

### Notable passes

- `B05`, `S01`, `S10` — a clean checkout builds and tests with documented
  commands, no external dependencies, and CI proves it on every push.
- `S07` — verified by reading every logging call: no window title, no personal
  data, only counts, pids, and error descriptions.
- `X02` — tiles and the menu bar item carry accessibility labels.
- `X04` — `openswitchr-diag` emits plain text with no colour and no Unicode
  decoration, so its output survives any pipe or log.
- `I01`, `I05` — the bundle carries its name and version, and embeds an icon
  generated from the same `WindowMark` the menu bar draws.
- `G01`, `G02` — this file exists, and its build, run, and validation commands
  were each executed rather than trusted.
- `B08`, `R02` — `CHANGELOG.md` follows Keep a Changelog and states the
  versioning policy.

### Not applicable

- **Deployable `D01`-`D06`.** Nothing is deployed. There is no environment.
- **Documentation `T01`-`T05`.** The product is an app.
- **`L04`-`L06`.** English only; no string catalogs exist to be validated.
- **`S06`.** No runtime configuration beyond user preferences.
- **`Y05`, `Y06`.** No third-party service receives anything, and thumbnails are
  held in memory under a byte budget, so nothing outlives a session.
- **Archived `A01`-`A04`.** Actively developed.

### Order of remediation

1. Merge, so the default branch stops contradicting the repository.
2. Enable secret scanning, push protection, and private vulnerability
   reporting; protect `main` and require CI. These are settings, not code.
3. Add `.github/conformance.yml` and the `trsdn-standard` topic, so the result
   is recorded and discoverable.
4. Add the `G03` and `G06` sections to this file — forbidden operations, and
   the generated paths — since both describe rules an agent is expected to
   follow and currently cannot read.
5. State the "none" cases: no data collected, no outbound connections, English
   only, and the known accessibility limits.
