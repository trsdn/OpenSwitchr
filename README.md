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
bash scripts/build-app.sh       # assemble and sign .build/release/OpenSwitchr.app

cp -R .build/release/OpenSwitchr.app /Applications/
open /Applications/OpenSwitchr.app
```

There is no Xcode project; the app bundle is assembled by the build script.

## Release

```bash
bash scripts/release_macos.sh v0.1.0   # build, notarize, sign a DMG into dist/
```

Notarization needs Apple credentials (`NOTARY_PROFILE`, or `APPLE_ID` plus
`APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`). Without them the script still emits
a signed, checksummed DMG and says clearly that it skipped notarization — that
build is for local testing only, since users would hit a Gatekeeper block.

See `RELEASE_CHECKLIST.md` for the full procedure.

## Measured behaviour

Measured on Apple Silicon, macOS 26.6, with 13 windows across 11 apps, using
`swift run openswitchr-diag --bench --capture`:

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
swift run openswitchr-diag                    # window index and AX linking
swift run openswitchr-diag --bench --capture  # plus timings
```

It reports per-app `CG` / `AX` / `LINKED` counts, which separates "the linking
heuristic failed" from "this app exposes no accessibility windows at all".

## Why not ⌘-Tab?

Because it cannot be made to work without private APIs, so OpenSwitchr does not
pretend otherwise and leaves it out of the settings entirely.

The system app switcher is a WindowServer symbolic hotkey, dispatched before
any session event tap sees the keystroke. Intercepting it needs either a
HID-level tap, which is root-only, or the private symbolic-hotkey API. A
`⌘-Tab` option would therefore be accepted in the UI and then silently never
fire, which is worse than not offering it. `⌥-Tab` is the default; `⌃-Tab` is
the alternative.

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
