# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Added

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

- `⌘-Tab` is now the default hold modifier, so OpenSwitchr replaces the macOS
  app switcher out of the box. `⌥-Tab` and `⌃-Tab` remain selectable, and an
  existing stored preference is left untouched.
- `⌘-Tab` is available again as a hold modifier, and it does replace the macOS
  app switcher. It had been removed on the assumption that the system switcher
  is dispatched before any session event tap; that assumption was never
  measured and is wrong. A session tap sees `⌘-Tab` and suppresses it: passing
  the same event through makes the Dock's switcher window appear, swallowing it
  does not.

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
