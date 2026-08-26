# AGENTS.md

Guidance for AI coding agents working in this repository.

## Hard rule: no GPL code

OpenSwitchr covers the same problem space as [DockDoor](https://github.com/ejbills/DockDoor)
and [AltTab](https://github.com/lwouis/alt-tab-macos). Both are **GPL-licensed**.
OpenSwitchr is MIT-licensed.

- **Never** copy, paste, translate, or derive code from those projects.
- **Do not** open their source files while implementing OpenSwitchr.
- Concepts and UX ideas are fine; implementations must be written from scratch
  against Apple's public documentation.
- Every dependency must be permissively licensed (MIT / Apache-2.0 / BSD).
  GPL dependencies are not acceptable.

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
