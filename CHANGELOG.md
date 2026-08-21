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
- `openswitch-diag` command-line harness for the behaviour that unit tests
  cannot reach: accessibility linking rates and capture timings.
- `scripts/rename-product.sh` to rename the product in one step, since
  "OpenSwitch" collides with the Linux Foundation's OpenSwitch (OPX).

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

### Fixed

- The single-window linking fallback no longer ignores the minimized check, so
  a minimized accessibility window can no longer be linked to an on-screen
  CoreGraphics window.
- Untitled helper and overlay surfaces with no accessibility counterpart are no
  longer listed as switchable windows.
