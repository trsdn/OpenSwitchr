# OpenSwitch

**One app instead of two.** Dock hover previews and an Alt-Tab style window
switcher, built on a single shared window index.

macOS ships with `⌘-Tab`, which switches *applications*, not *windows*. The two
best answers to that gap — [DockDoor](https://github.com/ejbills/DockDoor) for
Dock hover previews and [AltTab](https://github.com/lwouis/alt-tab-macos) for a
visual switcher — solve two halves of the same problem, and each pays the full
cost of doing so: enumerating every window, observing every change, and
capturing every thumbnail. Running both means paying twice.

OpenSwitch pays once. The window index, the event bus, the thumbnail cache, and
the window actions exist exactly once; the Dock previews and the switcher
overlay are thin readers on top.

> **Written from scratch.** DockDoor and AltTab are GPL-licensed. No code from
> either project was copied, translated, or derived. Concepts are shared;
> implementation is not. See [AGENTS.md](AGENTS.md).

---

## Features

- **Switcher overlay** — hold `⌥` and press `Tab` for every window on the
  current Space in most-recently-used order, with live thumbnails.
- **Type to filter** — start typing to narrow by app name or window title.
- **Dock hover previews** — hover a Dock icon to see that app's windows; click
  one to jump straight to it.
- **Window actions** — focus, minimize, restore, and close from either frontend.
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
bash scripts/build-app.sh       # assemble and sign .build/release/OpenSwitch.app

cp -R .build/release/OpenSwitch.app /Applications/
open /Applications/OpenSwitch.app
```

There is no Xcode project; the app bundle is assembled by the build script.

## Measured behaviour

Measured on Apple Silicon, macOS 26.6, with 13 windows across 11 apps, using
`swift run openswitch-diag --bench --capture`:

| Metric | Budget | Measured |
|---|---|---|
| Idle CPU | < 0.1 % | 0.0 % |
| Idle memory | < 60 MB | ~65 MB |
| Cold window index build | — | ~240 ms, off the main thread |
| Warm index rebuild | < 100 ms | ~51 ms mean |
| AX-to-CGWindowID link rate | — | 13/13 windows |
| 8 thumbnails, cold and parallel | — | ~540 ms, streamed into the UI |
| Thumbnail cache hit | — | < 0.1 ms |

Two design choices drive these numbers:

- **No polling.** Every update comes from an accessibility notification, an
  `NSWorkspace` notification, or the event tap. Nothing runs on a timer.
- **Batched accessibility reads.** Each accessibility read is a synchronous
  message to another process, so cost tracks round trips rather than data.
  Reading role, subrole, title, position, size, and minimized state in one
  batched message per window cut rebuilds from ~350 ms to ~75 ms; querying apps
  in parallel took cold builds from ~990 ms to ~240 ms.

## Diagnostics

The parts that depend on real windows cannot be unit tested, so they get a
command-line harness. Run it from a terminal that holds the Accessibility
permission:

```bash
swift run openswitch-diag                    # window index and AX linking
swift run openswitch-diag --bench --capture  # plus timings
```

It reports per-app `CG` / `AX` / `LINKED` counts, which separates "the linking
heuristic failed" from "this app exposes no accessibility windows at all".

## Scope: current Space only

Windows on other Spaces are deliberately not shown. The public accessibility
API reliably reports only the current Space; reaching the rest requires private
SkyLight calls, which are out of bounds here. The index rebuilds on every Space
change.

## Known limitation: the name

**OpenSwitch** collides with the Linux Foundation's
[OpenSwitch (OPX)](https://github.com/open-switch) network operating system.
Nothing has been published under this name yet, so the collision is currently
free to fix:

```bash
bash scripts/rename-product.sh OpenSwitchr
```

## License

MIT — see [LICENSE](LICENSE).
