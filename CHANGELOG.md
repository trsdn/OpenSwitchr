# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The switcher still fell back to icons for a busy Space even under the new *Previews up to*
  limit from 0.2.3, because a second, unrelated check — fitting every tile into three rows
  without scrolling — forced icons on its own once a Space had about 28 windows, on any
  display, regardless of the configured limit. Past that width and row ceiling, tiles now
  shrink to their floor and the (already scrollable) switcher grid scrolls for the rest,
  instead of giving up on previews. Only the *Previews up to* setting decides icons vs.
  previews now.

## [0.2.3] - 2026-09-21

### Fixed

- The switcher lost its previews and showed only icons whenever more than 12 windows were on the
  Space, however large the display, so a Space with 28 windows had no previews at all. The limit
  is now a setting, *Previews up to*, in the Appearance tab (4 to 60 windows, 30 by default). The
  tile size keeps its own legibility floor, so previews that would be too small still fall back to
  icons. The Dock preview keeps its own limit of 12, which is one application's windows.
- "Restore the shipped defaults" in the Apps tab now asks first, since it replaces every rule
  including the ones you added.
- The switcher and Dock preview tiles are now single buttons for VoiceOver, named
  "application: window title", with their state ("Minimized", or a hint for applications
  with no windows) spoken rather than shown only as a tooltip, and "Close window" and
  "Quit application" offered as actions. The window count is announced as "3 windows",
  and decorative symbols are hidden.
- The orange warning and the green "Granted" text in Settings were too light on the light
  background; the colour now stays on the icon and the text is the standard colour.
- The Permissions tab says that window titles and previews are read on this Mac and never sent
  anywhere.
- "Check for Updates" no longer carries an ellipsis, since it acts immediately.

### Added

- Releases from now on carry a GitHub build attestation, signed with the release
  pipeline's identity, so a download can be checked with
  `gh attestation verify OpenSwitchr-X.Y.Z.dmg --repo trsdn/macos-notarization-broker`.
  Nothing changes inside the app.

## [0.2.2] - 2026-09-20

### Added

- The switcher and the Dock preview now follow the system accessibility settings
  Reduce Motion (the selection no longer animates into view), Reduce Transparency
  (the blur becomes an opaque fill) and Increase Contrast (borders, tile fill,
  selection and small marks step up). With all three off nothing looks different.

### Fixed

- The installed app had a generic icon. Releases 0.2.0 and 0.2.1 shipped without the
  app icon because the release build never copied it into the bundle; the release
  build now includes it and refuses to build without it.

### Changed

- The menu bar menu now starts with the app's name and version, so it is clear whose
  menu it is when it opens.
- The version now has one home, the newest release heading in `CHANGELOG.md`. The
  source `Info.plist` holds a `__VERSION__` placeholder that `scripts/build-app.sh`
  and the release broker fill in, so a release no longer needs the number typed in
  two places. `scripts/check.sh` fails if a version is typed into `Info.plist`.

## [0.2.1] - 2026-09-19

### Fixed

- The German localization is now actually in the release. 0.2.0 was built by a toolchain that copied the string catalogs instead of compiling them, so it shipped English only; the release build now compiles them itself and refuses to ship without German.

## [0.2.0] - 2026-09-19

### Added

- Repository conformance record at `.github/conformance.yml`, assessed against
  version 1.5.1 of the trsdn Repository Quality Standard, with the reasoning
  behind every result in `docs/self-assessment.md` and the badge rendered from
  the record into `.github/badges/conformance.svg`. A scheduled workflow
  re-validates both, so a record that drifts from its badge, or an assessment
  that ages past the review cadence, turns the check red on its own.
- `scripts/check.sh`, the single command that validates a change before it is
  proposed: build with warnings as errors, tests, markdown lint, and the bundle
  metadata checks below. It needs no signing identity, no permissions, and no
  network, so it behaves the same on a laptop, in CI, and for an agent.
- Drift guards for the three facts nothing used to compare. The version in
  `Info.plist` is checked against the newest release heading in this file, and
  the minimum macOS version is checked across `Package.swift`,
  `scripts/build-app.sh`, and the README badge. All of them had been maintained
  by hand in parallel.
- Product identity in the bundle: repository URL, issue tracker URL, licence
  identifier, and copyright holder as `Info.plist` keys, plus the licence text
  copied into `Contents/Resources`. The About tab now reads its links back out
  of the bundle rather than hardcoding them a second time, so the shipped
  metadata and what the user sees cannot disagree.
- Issue forms for bug reports and proposals, a `CODEOWNERS` file, a Dependabot
  configuration for the pinned action versions, `.github/github-app.yml`, and a
  markdown lint workflow.
- `.gitattributes`, marking `Resources/AppIcon.icns` as generated. It is
  rewritten by every build, so hand-editing it accomplishes nothing.
- README sections stating the cases that were previously only implicit: the app
  collects nothing and opens no outbound connection, preferences live in
  `UserDefaults` under `com.openswitchr.app` and how to read or delete them,
  the project is English-only, and which accessibility limitations are known.
- `AGENTS.md` now names the operations an agent must not perform, the paths that
  are generated, and the review expectation for agent-authored changes.
- `WindowFilter`: one pure value type describing which windows a surface wants
  and in what order, applied by both frontends. Four axes — application scope,
  minimized handling, display scope, and order — with the switcher's
  configurable in Settings and the Dock preview's fixed and permissive, because
  the pointer already chose the application. Defaults reproduce the previous
  behaviour exactly.
- `openswitchr-diag --filters`, which applies the profiles to the windows
  actually open and checks the one axis unit tests cannot judge: that scoping
  by display leaves no window claimed by no display.
- Dock previews can switch instantly while one is already open, so the open
  delay applies to the first preview only and moving along the Dock does not
  wait again. On by default. A hover that resolves before the index has caught
  up is retried once the rebuild lands, rather than leaving the pointer on an
  icon with nothing shown.
- A per-application rule table (`AppRule`, `AppRuleTable`), keyed by
  bundle-identifier prefix, with two independent axes: hide a window outright
  (never / always / when its title matches), and stand aside for it — swallow
  nothing, raise nothing — while it is frontmost and full screen. Ships with
  verified defaults for the known correctness case: a remote desktop, screen
  share, or virtual machine running full screen now gets the switcher hotkey
  itself rather than an overlay raised over it. Full screen is detected once
  per rebuild, from the window's frame against the display it covers, and
  carried on `WindowInfo.isFullScreen` so the event tap never has to ask.
  `openswitchr-diag --filters` reports both against the windows actually open.
- A minimized window keeps its last good thumbnail. ScreenCaptureKit cannot
  capture a window in the Dock, so that image is the only preview there will
  be; the store now exempts it from the refresh age limit (which it could never
  satisfy), evicts it after every live entry when the byte budget is exceeded,
  and drops it when the window is restored so the first frame after restoring
  is not stale. The tile already dims a minimized preview and marks it as such.
- Icon-and-title tile mode, chosen deliberately instead of by accident. A
  "Tiles show" setting picks previews or icons only, and previews switch to
  icons on their own when Screen Recording is not granted (every capture would
  fail) or when a surface has more than twelve windows (each preview too small
  to identify). The threshold is a named constant per surface. In icon mode
  nothing calls `ThumbnailProvider.prefetch`, so a busy Space costs zero
  captures; the mode is decided when a panel opens and kept for that session,
  and the cache is left valid rather than cleared. For scale, eight cold
  parallel captures measured ~340 ms with `openswitchr-diag --bench --capture`.
- Switcher tiles can shrink so every window fits without scrolling
  ("Shrink switcher tiles so every window fits", on by default). The configured
  width is the upper limit and is never exceeded: with a few windows nothing
  changes, and with more than fit in the overlay's three visible rows the tile
  steps down in twenty point steps until they do. Sizes are quantised so the
  thumbnail cache keeps hitting and the step is what is captured, and below the
  legible floor the switcher uses icon tiles instead of a smaller image. The
  layout maths is `TileSizing`, pure and unit tested.
- Thumbnail captures are bounded, prioritised, and cancellable
  (`CaptureLimiter`, unit tested). At most four run at once instead of one per
  tile, the selected tile is asked for first and jumps the queue, and dismissing
  a panel cancels every capture that has not started, so they do not complete
  into a cache nobody will read. A cancelled request records nothing, so a later
  one simply tries again.

### Changed

- `main` is protected: pull requests are required, the three CI checks must
  pass, and force pushes and branch deletion are blocked. Secret scanning, push
  protection, Dependabot security updates, and private vulnerability reporting
  are enabled.
- The repository quality section of `AGENTS.md` was reassessed. It had described
  a default branch holding two files, which stopped being true when the work was
  merged, and it assessed against version 1.3.3 of a standard now at 1.5.1.
- Reassessed against version 1.11.1 of the standard (previously 1.5.1), the
  latest version actually tagged in `trsdn/.github` — the reusable conformance
  workflow resolves the standard at its published tag, and the untagged
  1.12.0 bump on its `main` is not yet consumable. No criterion regressed; the
  ten added since 1.5.1 were assessed for the first time and surfaced one real
  gap, `S12`: `actions/checkout@v4` and the reusable conformance workflow
  pinned to `@main` can both change underneath the repository.
  `docs/self-assessment.md` and the badge are updated to match.
- The rule deciding whether a CoreGraphics window with no accessibility
  counterpart belongs in the index moved out of `WindowIndex.apply` into
  `WindowAdmission.admits`, where it is documented and unit tested. Behaviour
  is unchanged.

### Fixed

- In-app updates from GitHub Releases (#30), through
  [AppUpdater](https://github.com/mxcl/AppUpdater) 4.1.2 pinned `exact:` with
  `Package.resolved` committed, the same setup as the sibling apps. **This is the
  app's first third-party dependency and its first network connection**, so the
  README's Privacy section, the project page and Settings now say so: one daily
  request to GitHub, no identifier, and **"Check for Updates Automatically" turns
  it off** entirely. The menu gains Check for Updates…, an update that is ready
  offers "Install and Restart", and the app stops its event tap, Dock observer and
  panels before the bundle is replaced. The schedule (`UpdateSchedule`: a daily
  check that wakes hourly so a slept-through deadline catches up, and survives a
  clock that moved back) and the state rules (`UpdateState`: a failed background
  check stays silent, a manual one always answers) are pure and unit tested.
  `THIRD_PARTY_NOTICES.txt` carries AppUpdater's (Unlicense) and its dependency
  Version's (Apache-2.0) licenses verbatim and is copied into the bundle. The
  broker side (an `OpenSwitchr-<semver>.dmg` asset, the dependency lock, the
  resource bundle) landed in trsdn/macos-notarization-broker#56, but **no release
  with the updater has been built, and a real update has never been run**, both
  recorded in `RELEASE_CHECKLIST.md`.
- Two German layout and wording fixes found by rendering the Settings views
  offscreen in German for the first time (#57): the "Präfix der Bundle-Kennung"
  label wrapped onto two lines and squeezed its own text field, so it is now the
  field's prompt; and the update explanation switched to informal "du" while every
  other string is impersonal. The other tabs, including the two labels #5 warned
  about, fit without truncation.
- The interface is localized, with German as the first additional language
  (#5). Two String Catalogs, `Localizable.xcstrings` for the app and `UI.xcstrings`
  for the shared views, are compiled by SwiftPM and copied into the app bundle by
  `scripts/build-app.sh`; counts use plural variants; the product name and the
  modifier symbols are never translated. `LocalizationCatalogTests` fails on an
  untranslated entry, a dropped placeholder, an incomplete plural, a lost product
  name, or a plain literal that never reached a catalog (mutation-tested). The
  German was written by an AI assistant and has not been reviewed by a native
  speaker. The release broker's `openswitchr` adapter now copies the `.lproj`
  directories too (trsdn/macos-notarization-broker#56), but no release has been
  built since, and a per-release check is in `RELEASE_CHECKLIST.md`. `Info.plist` gains
  `CFBundleDevelopmentRegion` and `CFBundleLocalizations`.
- The switcher can list running applications that have no open windows (off by
  default, "Applications with no windows"). They come after the windows, and
  choosing one activates the application and asks it to open a window by
  launching it again, which sends the reopen event a Dock click sends; not every
  application makes a window on that, and some make an unexpected one, which the
  setting says. Built when the overlay opens and only if the setting is on, from
  a list of running applications read once (10-18 ms measured here), so the
  index and its rebuild path keep resolving only processes that own a window. An
  entry is a `WindowInfo` marked `isApplicationOnly` with a synthetic id above a
  reserved base, so both frontends, the thumbnail cache and the actions already
  understand it, and the few that must differ (no capture, no raise) can ask.
  `WindowlessApplications` and the filter axis are unit tested, and
  `openswitchr-diag --filters` reports them against the real running applications.
- Optional scroll-to-cycle on a Dock icon (off by default): scrolling with the
  pointer on an application's icon focuses its next or previous window without
  opening a preview. It is the version the deferral said was the only one worth
  building: the scroll tap exists disabled, is enabled on hover-enter and disabled
  on hover-leave, and its callback also checks the event's location against the
  hovered icon, so a missed leave cannot leave scrolling swallowed anywhere else.
  Step accumulation (`ScrollStepper`: one step per event at most, rate-limited,
  reversal discards) and which window is next (`WindowCycle`: a stable order, not
  recency, so repeated steps visit every window instead of ping-ponging) are pure
  and unit tested. The callback's per-event work measured about 105 ns in a debug
  build.
- An optional second switcher hotkey (off by default): the hold modifier with the
  backtick key opens the switcher for the current application's windows only, the
  question that is awkward to express as a search. The profile is fixed and
  inherits every other axis from the configured filter (`SwitcherProfile`, unit
  tested), so it is one toggle rather than a second copy of the settings, and
  which key opens which profile is a tested lookup, so the tap callback stays
  trivial. The tap now remembers the key code it swallowed rather than assuming
  Tab.
- The per-application rules are editable: a new **Apps** tab lists them, adds one
  by bundle identifier prefix or from a running application, and restores the
  shipped defaults. Each hiding rule shows how many windows it removes right now
  (`AppRuleTable.hiddenCount`), so a rule that empties the switcher is noticed
  where it was set. Stored as JSON under `appRules`; nothing stored, or data that
  no longer parses, yields the defaults rather than an empty table, which would
  silently switch off the stand-aside protection. Editing a rule recomputes
  whether the hotkey stands aside immediately.
- A project page at `docs/index.html`, served by GitHub Pages: what it is, who it
  is for, status and version, how to get it, the privacy statement, and the
  repository, license, security and support links. One page, no scripts, no
  third-party resources, no cookies, styled with Instrument Workshop v1.5.1
  vendored unmodified with its version recorded in `docs/assets/VERSION`. The
  Published Sites criteria (`W01`-`W08`) are now assessed and pass; the network
  review behind `W07` is in `docs/self-assessment.md`.
- `openswitchr-diag --check-budgets` turns the measured performance numbers
  into thresholds that can fail: cold and warm index rebuild, cold thumbnails,
  and cache hits, checked against budgets kept in one file next to the harness.
  It exits non-zero when a budget is exceeded or could not be measured (a check
  that skipped what it could not measure would go green the day the measurement
  broke). Wall-clock and machine-dependent by nature, so it is a step in
  `RELEASE_CHECKLIST.md`, not a hosted CI gate. The comparison is
  `PerformanceBudget.evaluate`, pure and unit tested.
- The Dock preview is placed from where the Dock item actually is
  (`DockPanelPlacement`, unit tested). A left or right Dock was misdetected as a
  bottom one, because the edge check required the icon to be within 4 pt of the
  screen edge and a Dock icon sits inside the Dock's own padding; the edge is now
  the nearest one. The screen is the one containing the item's centre instead of
  `NSScreen.main`, the panel is clamped inside that screen's visible frame, and a
  side Dock gets a scrolling column rather than a row that runs off the screen.
- The Dock preview's lifetime is one state machine (`DockPanelLifecycle`, unit
  tested) instead of a scheduled hide plus a fire-time check. The Dock item and
  the panel are one hover region: moving between them cancels a pending hide,
  and a stale timer does nothing. A panel with no pointer movement and no
  interaction for ten seconds now closes itself; the timer exists only while a
  panel is on screen and `hide()` cancels it on every exit.
- `openswitchr-diag --probe-app` decides whether focus moved by the frontmost
  window's `CGWindowID` instead of by a rendered "app — title" string, which
  read a correct switch as a failure whenever two windows shared a title. The
  Dock preview's "hidden on exit" check now polls up to three seconds instead of
  sleeping a fixed 900 ms, which reported the preview still visible once and
  never again.
- Dependabot now watches the Swift package as well as the workflows. AppUpdater is
  pinned `exact:`, which does not move by itself, so an upstream fix would never
  arrive; the code that downloads and installs updates should not age quietly.
- The two sibling `### Added` headings under `0.1.0` in this file are merged
  into one, which is both a lint failure and genuinely confusing to read.
- `actions/checkout` and the reusable `trsdn/.github` conformance workflow are
  pinned to a full commit SHA instead of `@v7` and `@main`. Both were mutable
  references that could change underneath this repository without a commit
  here — the `S12` gap the last reassessment found. `S12` moves to `pass`.
- A modifier release landing in the gap between the hotkey opening the
  overlay and the overlay reporting itself visible no longer strands the
  overlay on screen. `HotkeySessionGate` tracks the open request separately
  from confirmed visibility, so a fast tap of the hotkey still commits.
- The switcher overlay now picks up an index rebuild that lands after it
  opened, instead of showing a stale list — including an empty one under a
  restrictive filter — for the rest of the session. Selection is preserved by
  window identity across the refresh, not by position.

## [0.1.0] - 2026-08-30

### Added

- Shared window foundation used by both frontends: `WindowIndex` (single source
  of truth), `WindowEventBus` (accessibility and `NSWorkspace` notifications,
  no polling), `ThumbnailStore` (ScreenCaptureKit behind an LRU cache with a
  hard byte budget), `WindowActions`, and `WindowMatcher`.
- `AXWindowLinker`, which reconstructs the accessibility-to-`CGWindowID` link
  from process, frame, title, and minimized state, without the private
  `_AXUIElementGetWindow`.
- Switcher overlay on a non-activating `NSPanel`, driven by a `CGEventTap`:
  hold `⌘`, press `Tab`, navigate by keyboard or mouse, type to filter. `⌥` and
  `⌃` are selectable in Settings.
- Dock hover previews driven by an accessibility observer on the Dock, with a
  fallback notification path and no mouse polling.
- Menu bar app (`LSUIElement`) with settings, permission onboarding, and
  launch-at-login via `SMAppService`.
- `openswitchr-diag` command-line harness for the behaviour that unit tests
  cannot reach: accessibility linking rates and capture timings.
- `scripts/rename-product.sh`, which renames the product across source
  directories, entitlements, bundle identifier, code, docs, and scripts in one
  step. Used to settle on **OpenSwitchr** — "Open Switcher" without the *e* —
  because plain "OpenSwitch" is the Linux Foundation's OpenSwitch (OPX)
  network operating system.

- Preview size, thumbnail refresh rate, and optional close and quit buttons on
  every preview tile. Refresh rate trades thumbnail freshness for capture cost
  and is expressed purely as an age limit — nothing runs on a timer, so the idle
  cost of "Always fresh" is still 0.0 %. The buttons are off by default, because
  they put destructive targets a few pixels from the one that focuses a window;
  close sits top left and quit top right, in opposite corners rather than side
  by side, because only one of the two can be undone.
- Release process via `trsdn/macos-notarization-broker`, documented in
  `RELEASE_CHECKLIST.md`. Apple credentials never enter this repository; the
  broker builds from a pinned commit and signs with its own code.
- `scripts/make_dmg.sh` for local, explicitly unnotarized test packaging.
- GitHub Actions: `ci.yml` builds with warnings-as-errors and runs the tests,
  and `secret-scan.yml` guards against committed credentials. Neither uses a
  secret, an environment, or write permissions.
- An app icon, and a menu bar glyph drawn from the same geometry. `WindowMark`
  in `OpenSwitchrUI` owns the two overlapping windows; `openswitchr-icon`
  renders `Resources/AppIcon.icns` from it and `build-app.sh` re-runs on every
  build, so the icon cannot fall behind the glyph. The icon takes the filled
  weight and the menu bar the outlined one, because solid art that carries a
  1024 pt icon collapses into a blob at 15 pt.

### Changed

- The switcher opens even when its filter matches nothing, and says so. The
  event tap swallows the hotkey either way, so returning early left `⌘-Tab`
  inert with the system switcher still suppressed — reachable on purpose once a
  restrictive filter exists, not just on an empty Space.
- The initial selection is derived from where the current window ended up in the
  list rather than from a fixed offset of 1, which only ever held while the list
  was in most-recently-used order and still contained that window.
- `⌘-Tab` is now the default hold modifier, so OpenSwitchr replaces the macOS
  app switcher out of the box. `⌥-Tab` and `⌃-Tab` remain selectable, and an
  existing stored preference is left untouched.
- `⌘-Tab` is available again as a hold modifier, and it does replace the macOS
  app switcher. It had been removed on the assumption that the system switcher
  is dispatched before any session event tap; that assumption was never
  measured and is wrong. A session tap sees `⌘-Tab` and suppresses it: passing
  the same event through makes the Dock's switcher window appear, swallowing it
  does not.

### Performance

- Rebuild the window index only when a frontend is about to be shown. A single
  application retitling one window fifteen times a second was enough to keep
  the index rebuilding continuously, costing 3–7 % CPU on an otherwise idle
  machine. Events now mark the index stale and the rebuild happens on the path
  that opens the overlay or a Dock preview, where ~9 ms disappears behind the
  window that is already being drawn. Idle CPU is back to 0.0 %.

- Read window attributes with `AXUIElementCopyMultipleAttributeValues` instead
  of one message per attribute: warm index rebuilds went from ~350 ms to
  ~75 ms.
- Query each app's accessibility tree in parallel and off the main thread: cold
  builds went from ~990 ms to ~240 ms, and the main thread no longer waits on
  unresponsive apps.
- Coalesce concurrent `SCShareableContent` queries. A cold burst of eight
  thumbnails previously fired eight redundant queries and captures did not
  overlap; parallel capture went from ~730 ms to ~540 ms.
- Resolve only the processes that own windows, and cache them.
  `NSWorkspace.runningApplications` walks every process on the system and
  accounted for ~60 % of rebuild time in a sampled profile, while a rebuild
  only needs the handful of processes with windows on screen. Warm rebuilds
  went from ~51 ms to ~8.6 ms.
- Build the overlay's `NSHostingView` once and replace only its root view.
  Recreating it on every render made the overlay cost ~50 ms to appear and
  repeated the same work on every selection change; it now appears in
  ~21–24 ms.

### Fixed

- **The release build did not compile at all, while CI was green.** Published
  builds are produced on `macos-15`, but CI only ever ran `macos-latest`. On the
  macOS 26 SDK, `SCScreenshotManager.captureImage` is annotated such that
  handing it a content filter built inside the `ThumbnailStore` actor is
  accepted; on the macOS 15 SDK it is a `sending` violation and a hard error, so
  the very first notarization request failed on a tree that had passed every
  check. The capture now crosses the actor boundary as `Sendable` values in both
  directions, and CI builds and tests on `macos-15` as well, so the toolchain
  that produces releases can no longer go untested.

- **Windows went unlinked right after launch, so the switcher raised the wrong
  one.** The accessibility timeout was 0.25 s per app. An app's first
  accessibility message is far more expensive than its later ones, and a cold
  rebuild sends that first message to every app at once, so the slowest
  handshakes ran out of the budget and their windows arrived with no
  accessibility element — measured at 15–16 of 21 windows on a cold run, with a
  different set of apps failing each time, recovering to 21 of 21 only once the
  connections were warm. Thumbnails still looked right, because those come from
  the `CGWindowID`, but every *action* goes through the element, so activating a
  tile fell back to a guess in exactly the moment after launch. The budget is
  now 1.0 s, which is affordable because it is spent in parallel: the app only
  rebuilds through `rebuildConcurrently()`, so the timeout bounds the slowest
  single app rather than the sum, and cold rebuilds measured 240–350 ms either
  way. Cold runs now link every window.

- **Thumbnails disappeared over a session and never came back.** A tile's
  `onAppear` was the only thing that ever requested a capture, and both panels
  are merely ordered out rather than torn down, so their SwiftUI tree survives
  and that fires exactly once per window per launch. Everything else only
  removed: `retain(only:)` after each index rebuild, and `clear()` on every
  Space change, which drops all of them at once. Any image lost that way was
  lost until relaunch, so previews decayed into icon tiles. The controllers now
  request captures for the set they are about to show, on the path that shows
  it rather than from a `render()` that also runs on hover.
- **The thumbnail refresh-rate setting did nothing once a preview had loaded.**
  The provider returned early whenever an image was already present, so the age
  limit in `ThumbnailStore` — which is what the setting configures — was never
  consulted again for that window.
- **The switcher's order ignored every window switch inside an app.** A focus
  event carries a pid, and the window was resolved by taking the first entry of
  that pid out of `windows` — a list that is sorted most-recently-used first, so
  the answer was by construction the window that was *already* on top. Focusing
  a second Finder window re-promoted the first one and the order never moved,
  which made `⌘-Tab` feel arbitrary for anyone running more than one window per
  app. `kAXFocusedWindowChangedNotification` carries the newly focused window as
  its own element, measured against Safari with three windows, so that element
  now decides and the pid is only a fallback. Verified against a real app:
  focusing each of three windows in turn now puts each one at the top, where
  before only the incumbent was ever promoted.
- **Focus changes in a background app were credited to the foreground one.** The
  same callback read `NSWorkspace.frontmostApplication` instead of the pid of
  the element that had actually changed.
- **Minimized windows vanished from the switcher.** macOS relabels a window's
  accessibility subrole from `AXStandardWindow` to `AXDialog` the moment it goes
  to the Dock — measured on both Activity Monitor and Preview, macOS 26.6 —
  while its role, title, position, and size stay exactly as they were. The
  subrole filter therefore reported *zero* accessibility windows for the app,
  nothing linked, and `WindowIndex` dropped the CoreGraphics entry for no longer
  being on screen. Minimized now outranks the subrole, so a window in the Dock
  stays listed, keeps its accessibility element, and is restored by activating
  its tile.
- **The Settings window opened behind other windows.** `LSUIElement` keeps
  OpenSwitchr out of the Dock, which also means opening a window never activates
  the app, and `SettingsLink` offers no action to hook. The menu item now calls
  `openSettings()` itself so `NSApp.activate()` can run alongside it. Measured
  by z-order rather than by eye: the window now opens at index 0 of the on-screen
  normal windows, with OpenSwitchr frontmost.
- **`build-app.sh` could not find a signing identity when two were installed.**
  awk's `exit` still runs the `END` block, so a keychain holding both an Apple
  Development and a Developer ID Application certificate printed two
  fingerprints. `codesign` read them as one newline-joined identity and failed
  with "no identity found", leaving an assembled but unsigned bundle.

- **Clicking a Dock preview raised the wrong window.** Two independent faults
  produced one symptom. The window snapshot derived z-order from the position
  of each window in a `CGWindowListCopyWindowInfo(.optionAll)` listing, but
  front-to-back order is only documented for `.optionOnScreenOnly`; two
  TextEdit windows 29 pixels apart were reported at positions 15 and 603 of 704
  while the on-screen listing had them correctly adjacent at 145 and 146. That
  bogus order also seeded the switcher's MRU list. On top of it, the linker
  broke score ties with Swift's `sort`, which is not guaranteed stable: four
  Microsoft Edge windows sharing a frame *and* a title produced four equally
  good pairings and the winner was effectively drawn at random. The thumbnail
  was never wrong — it comes from the `CGWindowID` — so the tile showed the
  window the user wanted while the click went to a different one. Z-order now
  comes from the on-screen listing, and the linker breaks ties by matching
  accessibility depth against z-order depth, with every remaining comparison
  fully determined. Raising a specific window went from 50 % to 100 % correct
  across every Edge and TextEdit window on the test machine.
- Accessibility titles decorated by the application no longer score as a
  mismatch. Microsoft Edge reports `Connect Form` to CoreGraphics and `Connect
  Form – Standbymodus - Microsoft Edge – Geschäftlich` to accessibility, so
  demanding equality scored every one of its windows zero on title and left the
  frame to decide alone. A substantial shared prefix now counts as a moderate
  signal.

- Preview size had no visible effect beyond the first capture. Thumbnails were
  cached without their captured size and never re-captured when the setting
  grew, so enlarging previews only scaled a small bitmap up and every preview
  turned soft. Captures are now tracked by size and re-taken when the requested
  size grows meaningfully.
- **The switcher hotkey stopped working after a while.** The event tap ran its
  callback on the main run loop, where it queued behind SwiftUI rendering and
  index work, and the system disables a tap whose callback is late. Re-enabling
  only rescued the *next* keystroke, so the one the user pressed was swallowed
  and nothing happened. The tap now owns a dedicated run loop thread and reads
  a locked snapshot instead of main-actor state, so it never waits on the UI.
  A tap disabled behind the app's back is also re-enabled on application
  activation, which needs no timer.
- **Hovering the same Dock icon a second time showed nothing.** The Dock never
  reports that the pointer left it, so the hover monitor kept treating the last
  icon as still hovered, and returning to it looked identical to not moving at
  all. Previews now reset that state whenever a hover ends.
- **The app did nothing until the menu bar icon was clicked.** Startup ran from
  a `task` on the `MenuBarExtra`'s content, and a `.menu`-style menu bar extra
  builds its content lazily when the menu is opened. A user who launched the
  app and pressed the hotkey got an app that had never started its window
  index, event tap, or Dock observer. Startup now happens in
  `applicationDidFinishLaunching`, where it does not depend on any view
  existing.
- Granting accessibility no longer requires finding a "try again" button. The
  app now waits for the grant and starts itself when it arrives.
- The single-window linking fallback no longer ignores the minimized check, so
  a minimized accessibility window can no longer be linked to an on-screen
  CoreGraphics window.
- Untitled helper and overlay surfaces with no accessibility counterpart are no
  longer listed as switchable windows.
- Settings controls no longer snap back to their previous value. `PreferencesStore`
  exposed every preference as a computed property over `UserDefaults`, and the
  `@Observable` macro only tracks *stored* properties, so SwiftUI never
  registered a dependency and re-rendered the old value after a change. The
  preferences are now stored properties that write through on `didSet`.
- The thumbnail memory budget now takes effect immediately instead of at the
  next launch.
- The event tap no longer swallows every Tab key-up system-wide. Only the
  key-up matching a Tab that was actually swallowed on the way down is
  consumed, so plain Tab keeps moving focus in other apps.
- A failed event tap installation is now surfaced in the menu bar and settings
  instead of leaving the switcher silently dead.
