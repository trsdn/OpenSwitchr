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
└── OpenSwitchr/       App wiring: menu bar, hotkey tap, controllers, settings.
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
- **Keep the event tap callback trivial.** State transition only — no capture,
  no layout, no allocation-heavy work. A slow callback gets the tap disabled by
  the system.
- **Startup belongs to the app lifecycle, not to a view.** A `.menu`-style
  `MenuBarExtra` builds its content lazily when the user opens the menu, so
  anything started from that content never runs for a user who just launches
  the app and presses the hotkey. `AppDelegate` owns `AppModel` and starts it in
  `applicationDidFinishLaunching`. This shipped broken once and no test caught
  it, because every test exercised the core directly.
- **Signing identity must stay stable.** TCC permissions are tied to the code
  signature; `build-app.sh` aborts on an ad-hoc signature on purpose.

## Verifying the app, not just the core

The tests and `openswitchr-diag` both drive the core directly, so they cannot
tell you whether the *app* works. Three failures hid behind green tests: the app
never started, settings could not be changed, and hovering the same Dock icon
twice worked only the first time. Verify end to end with `openswitchr-diag
--probe-app`, which drives the installed bundle with synthetic events and
watches the window server:

- Post `⌥`+`Tab` with `CGEvent`, then poll `CGWindowListCopyWindowInfo` for a
  window owned by `OpenSwitchr` to time how long the overlay takes to appear.
- Move the pointer onto a Dock icon (its frame comes from the Dock's own
  accessibility tree) and look for the preview panel the same way.
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
warm.

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
