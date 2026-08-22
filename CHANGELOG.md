# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Shared window foundation used by both frontends: `WindowIndex` (single source
  of truth), `WindowEventBus` (accessibility and `NSWorkspace` notifications,
  no polling), `ThumbnailStore` (ScreenCaptureKit behind an LRU cache with a
  hard byte budget), `WindowActions`, and `WindowMatcher`.
- `AXWindowLinker`, which reconstructs the accessibility-to-`CGWindowID` link
  from process, frame, title, and minimized state, without the private
  `_AXUIElementGetWindow`.
- Switcher overlay on a non-activating `NSPanel`, driven by a `CGEventTap`:
  hold `⌥`, press `Tab`, navigate by keyboard or mouse, type to filter.
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

### Performance

- Read window attributes with `AXUIElementCopyMultipleAttributeValues` instead
  of one message per attribute: warm index rebuilds went from ~350 ms to
  ~75 ms.
- Query each app's accessibility tree in parallel and off the main thread: cold
  builds went from ~990 ms to ~240 ms, and the main thread no longer waits on
  unresponsive apps.
- Coalesce concurrent `SCShareableContent` queries. A cold burst of eight
  thumbnails previously fired eight redundant queries and captures did not
  overlap; parallel capture went from ~730 ms to ~540 ms.

### Added

- Release process via `trsdn/macos-notarization-broker`, documented in
  `RELEASE_CHECKLIST.md`. Apple credentials never enter this repository; the
  broker builds from a pinned commit and signs with its own code.
- `scripts/make_dmg.sh` for local, explicitly unnotarized test packaging.
- GitHub Actions: `ci.yml` builds with warnings-as-errors and runs the tests,
  and `secret-scan.yml` guards against committed credentials. Neither uses a
  secret, an environment, or write permissions.

### Changed

- Removed `⌘-Tab` from the hold-modifier choices. macOS dispatches it to the
  system app switcher before any session event tap, so the setting could be
  selected but would never fire. Stored values fall back to `⌥`.

### Fixed

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
