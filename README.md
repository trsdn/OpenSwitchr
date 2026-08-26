# OpenSwitchr

**One app instead of two.** Dock hover previews and an Alt-Tab style window
switcher, built on a single shared window index.

macOS ships with `⌘-Tab`, which switches *applications*, not *windows*. The two
best answers to that gap — [DockDoor](https://github.com/ejbills/DockDoor) for
Dock hover previews and [AltTab](https://github.com/lwouis/alt-tab-macos) for a
visual switcher — solve two halves of the same problem, and each pays the full
cost of doing so: enumerating every window, observing every change, and
capturing every thumbnail. Running both means paying twice.

OpenSwitchr pays once. The window index, the event bus, the thumbnail cache, and
the window actions exist exactly once; the Dock previews and the switcher
overlay are thin readers on top.

> **Written from scratch.** DockDoor and AltTab are GPL-licensed. No code from
> either project was copied, translated, or derived. Concepts are shared;
> implementation is not. See [AGENTS.md](AGENTS.md).

---

## Features

- **Switcher overlay** — hold `⌘` and press `Tab` for every window on the
  current Space in most-recently-used order, with live thumbnails. `⌥` and `⌃`
  are available in Settings if you would rather keep the system switcher.
- **Type to filter** — start typing to narrow by app name or window title.
- **Dock hover previews** — hover a Dock icon to see that app's windows; click
  one to jump straight to it.
- **Window actions** — focus, minimize, restore, and close from either frontend.
- **Minimized windows included** — a window in the Dock is still listed, dimmed
  and marked, and activating its tile restores it.
- **Menu bar app** — no Dock icon, no window of its own.

## Status

Early. The core is implemented and measured; the release pipeline is not built
yet. There is no published binary.

## Requirements

- macOS 15 or later, Apple Silicon
- **Accessibility** permission (window enumeration and window actions)
- **Screen Recording** permission (thumbnails; the app degrades to icon tiles
  without it)

## Build

```bash
swift build -c release          # compile
swift test                      # pure-logic tests
bash scripts/build-app.sh       # assemble and sign .build/release/OpenSwitchr.app

cp -R .build/release/OpenSwitchr.app /Applications/
open /Applications/OpenSwitchr.app
```

There is no Xcode project; the app bundle is assembled by the build script.
The app icon is generated rather than checked in as an opaque binary —
`swift run openswitchr-icon` renders `Resources/AppIcon.icns` from the same
`WindowMark` the menu bar glyph is drawn from, and `build-app.sh` re-runs it on
every build so the two cannot drift apart.

## Release

Distributable builds come from
[`trsdn/macos-notarization-broker`](https://github.com/trsdn/macos-notarization-broker),
which builds, signs and notarizes from a pinned commit without any Apple
credential ever reaching this repository:

```bash
scripts/request.sh openswitchr v0.1.0   # run from a broker checkout
```

`scripts/build-app.sh` and `scripts/make_dmg.sh` here are for local testing
only. They produce a signed but **unnotarized** DMG, which would trip Gatekeeper
on someone else's machine.

See `RELEASE_CHECKLIST.md` for the full procedure.

## Measured behaviour

Measured on Apple Silicon, macOS 26.6, with 17 windows across 15 apps, using
`swift run openswitchr-diag --bench --capture` plus synthetic-event probes
driving the installed, signed app:

| Metric | Budget | Measured |
|---|---|---|
| Idle CPU | < 0.1 % | 0.0 % |
| Idle memory | < 60 MB | ~17–24 MB |
| Overlay on screen after the hotkey | < 100 ms | ~16–24 ms |
| Dock preview on screen after hover | < 100 ms | ~2–8 ms |
| Cold window index build | — | ~159 ms, off the main thread |
| Warm index rebuild | < 100 ms | ~8.6 ms mean |
| AX-to-CGWindowID link rate | — | 17/17 windows |
| 8 thumbnails, cold and parallel | — | ~540 ms, streamed into the UI |
| Thumbnail cache hit | — | < 0.1 ms |

The first overlay after launch costs ~200 ms rather than ~22 ms, because
SwiftUI, the panel, and the first capture are all still cold. Every subsequent
invocation is warm.

Four design choices drive these numbers:

- **No polling.** Every update comes from an accessibility notification, an
  `NSWorkspace` notification, or the event tap. Nothing runs on a timer, with
  one deliberate exception: waiting for a TCC grant, which the system reports
  through no other means.
- **Batched accessibility reads.** Each accessibility read is a synchronous
  message to another process, so cost tracks round trips rather than data.
  Reading role, subrole, title, position, size, and minimized state in one
  batched message per window cut rebuilds from ~350 ms to ~75 ms; querying apps
  in parallel took cold builds from ~990 ms to ~240 ms.
- **Only windowed processes are resolved.** `NSWorkspace.runningApplications`
  walks every process on the system and accounted for roughly 60 % of rebuild
  time in a sampled profile, though a rebuild only needs the few processes that
  own windows. Resolving those by pid and caching them took warm rebuilds from
  ~51 ms to ~8.6 ms.
- **The overlay's hosting view is built once.** Recreating `NSHostingView` on
  every render cost ~30 ms per keystroke and made the first overlay far more
  expensive than it needed to be.
- **The index is only rebuilt when something is on screen.** One window that
  retitles itself fifteen times a second — a VPN client counting down is
  enough — otherwise keeps rebuilding a list nobody is reading, which measured
  3–7 % CPU on an idle machine. Events now mark the index stale, and the
  rebuild is paid on the path that opens the overlay or a Dock preview, where
  it costs ~9 ms and is hidden behind the window that is already appearing.

## Diagnostics

The parts that depend on real windows cannot be unit tested, so they get a
command-line harness. Run it from a terminal that holds the Accessibility
permission:

```bash
swift run openswitchr-diag                    # window index and AX linking
swift run openswitchr-diag --bench --capture  # plus timings
swift run openswitchr-diag --probe-app        # drive the *installed* app
```

It reports per-app `CG` / `AX` / `LINKED` counts, which separates "the linking
heuristic failed" from "this app exposes no accessibility windows at all".

`--probe-app` is the only check that exercises the shipping app rather than the
core: it posts a synthetic hotkey, measures how long the overlay takes to
appear, confirms focus actually moved by reading the CoreGraphics z-order, then
hovers a Dock icon *twice* and times both previews. The core passing its tests
says nothing about whether the app wired it up — two release-blocking bugs got
through exactly that gap.

## ⌘-Tab

`⌘-Tab` is the default, and it replaces the macOS app switcher while OpenSwitchr
runs. Quitting the app gives the system switcher back, and `⌥-Tab` and `⌃-Tab`
are available in Settings for anyone who would rather leave `⌘-Tab` alone.

This project previously claimed the opposite — that the system switcher is a
WindowServer symbolic hotkey dispatched before any session tap, making `⌘-Tab`
impossible without private APIs. That was an assumption, and it was wrong. A
session-level tap both sees `⌘-Tab` and suppresses it. The measurement that
settled it: passing the same event through makes the Dock's switcher window
appear, swallowing it does not. Comparing against a baseline mattered, because
the Dock always owns a window and a naive check reports the switcher as present
either way.

Choosing `⌘-Tab` replaces the system switcher only while OpenSwitchr runs.
Quitting the app gives it back, and `openswitchr-diag --probe-app` asserts the
suppression on every run.

## Previews

Three settings control what the preview tiles cost you:

| Setting | Default | Effect |
|---|---|---|
| Preview size | 200 pt | Tile width in both frontends. Growing it re-captures thumbnails, so previews stay sharp instead of being scaled up. |
| Refresh rate | 5 s | How old a cached thumbnail may be before the next request re-captures it. Nothing runs on a timer: this is an age limit checked when a preview is actually about to be shown, so even "Always fresh" leaves idle CPU at 0.0 %. |
| Close button | off | Two targets on each tile while the pointer is over it: close this window (top left) and quit the whole app (top right, red). Off by default, because they put destructive actions a few pixels from the target that focuses a window. |

Closing a window from a tile removes it from the index immediately rather than
waiting for the accessibility notification, which only marks the index stale —
otherwise the tile of an already-closed window would stay on screen. Quitting
deliberately does *not* prune tiles: `terminate()` is a request, and an app with
unsaved work may put up a dialog and stay. The panel dismisses instead, which
also stops it covering that dialog.

## Scope: current Space only

Windows on other Spaces are deliberately not shown. The public accessibility
API reliably reports only the current Space; reaching the rest requires private
SkyLight calls, which are out of bounds here. The index rebuilds on every Space
change.

## The name

**OpenSwitchr** is "Open Switcher" without the *e*, in the same spirit as
OpenWritr. The dropped vowel is not only decoration: plain "OpenSwitch" is
taken by the Linux Foundation's
[OpenSwitch (OPX)](https://github.com/open-switch) network operating system.

If the name ever needs to change again, `scripts/rename-product.sh` rewrites
source directories, the entitlements file, the bundle identifier, and every
reference in code, docs, and scripts in one step.

## License

MIT — see [LICENSE](LICENSE).
