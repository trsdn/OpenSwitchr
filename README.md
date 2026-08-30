# OpenSwitchr

[![License: MIT](https://img.shields.io/github/license/trsdn/OpenSwitchr?label=license)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)](#requirements)
[![CI](https://github.com/trsdn/OpenSwitchr/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/trsdn/OpenSwitchr/actions/workflows/ci.yml)
[![Latest tag](https://img.shields.io/github/v/tag/trsdn/OpenSwitchr?label=release)](https://github.com/trsdn/OpenSwitchr/releases)
[![Conformance](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Ftrsdn%2FOpenSwitchr%2Fmain%2F.github%2Fconformance.yml&query=%24.state&label=conformance)](.github/conformance.yml)

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

Early, and actively developed. The core is implemented and measured, `v0.1.0`
is tagged, and releases run through the notarization broker. There is no
published binary yet, so installing means building from source.

## Requirements

- macOS 15 or later, Apple Silicon
- **Accessibility** permission (window enumeration and window actions)
- **Screen Recording** permission (thumbnails; the app degrades to icon tiles
  without it)

## Build

```bash
swift build -c release          # compile
swift test                      # pure-logic tests
bash scripts/check.sh           # build, tests, markdown, and bundle metadata
bash scripts/build-app.sh       # assemble and sign .build/release/OpenSwitchr.app

cp -R .build/release/OpenSwitchr.app /Applications/
open /Applications/OpenSwitchr.app
```

`scripts/check.sh` is the single validation command: it builds with warnings as
errors, runs the tests, lints the markdown, and asserts that the version in
`Info.plist` still agrees with `CHANGELOG.md`. It needs no signing identity, no
permissions, and no network, so it runs the same on a laptop, in CI, and for an
agent.

There is no Xcode project; the app bundle is assembled by the build script.
The app icon is generated rather than checked in as an opaque binary —
`swift run openswitchr-icon` renders `Resources/AppIcon.icns` from the same
`WindowMark` the menu bar glyph is drawn from, and `build-app.sh` re-runs it on
every build so the two cannot drift apart. That file is marked
`linguist-generated` in `.gitattributes`; editing it by hand accomplishes
nothing, because the next build overwrites it.

## Configuration

Everything is configured from the menu bar item → **Settings**. There is no
configuration file and no environment variable.

Preferences are stored in `UserDefaults` under the `com.openswitchr.app` suite,
which on disk is `~/Library/Preferences/com.openswitchr.app.plist`. To inspect
or reset them:

```bash
defaults read com.openswitchr.app             # show every stored preference
defaults delete com.openswitchr.app <key>     # restore one registered default
defaults delete com.openswitchr.app           # restore all of them
```

Every setting takes effect immediately; none of them requires a relaunch.

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

## Privacy

OpenSwitchr collects nothing and transmits nothing. Stated explicitly, because
"no privacy policy" and "no data collection" look identical from the outside:

- **No outbound connections.** The app opens no network connection of any kind.
  There is no update check, no license check, and no remote configuration.
- **No telemetry, analytics, or crash reporting.** None is present, so there is
  nothing to opt out of.
- **No third-party services.** No service, and no AI provider, receives anything
  from this app. It has no account and no identifier.
- **Window titles never leave the process.** They are read to render and filter
  tiles. The unified log deliberately records only counts, pids, and error
  descriptions, so a log someone pastes into an issue cannot expose what they
  had open.
- **Thumbnails live in memory only.** ScreenCaptureKit images are held in an LRU
  cache under a hard byte budget and are never written to disk. They do not
  outlive the process; quitting the app is the whole of the deletion story.
- **The only thing stored on disk is your preferences**, in `UserDefaults` under
  `com.openswitchr.app`. See [Configuration](#configuration) for how to read,
  export, or delete them.

Two permissions are required, and both stay local: **Accessibility** to
enumerate windows, receive the hotkey, and raise a window; **Screen Recording**
to capture thumbnails. Both are revocable in System Settings → Privacy &
Security, and the app degrades to icon-only tiles without the second.

One caveat that is about this page rather than the app: viewing this README on
github.com loads the badge images at the top from `img.shields.io`, which
observes the request the way any remote image does. Nothing in the app itself
contacts that host, or any other.

## Language

English only. Every user-facing string, every command-line message, and every
document in this repository is English, and there is no localization
infrastructure — no string catalogs, no `.lproj` directories, no translation
pipeline. This is a declared state rather than an oversight; adding a language
is tracked in [#5](https://github.com/trsdn/OpenSwitchr/issues/5).

## Accessibility

What works, and what does not:

- **The switcher is fully keyboard-driven.** Hold the modifier, `Tab` and
  `⇧-Tab` move the selection, typing filters, `Escape` cancels, releasing the
  modifier commits. The selected tile carries a visible indicator, and tiles
  expose an accessible name and role to VoiceOver, as does the menu bar item.
- **Meaning never rests on colour alone.** The quit control on a tile is red
  *and* a distinct glyph in the opposite corner from the close control; a
  minimized window is dimmed *and* explicitly marked.

Known limitations, stated rather than left implicit:

- **Dock hover previews are pointer-only.** They are triggered by the pointer
  entering a Dock icon, so there is no keyboard route to them. This is inherent
  to the gesture; the switcher overlay reaches every window without a pointer.
- **Behaviour under enlarged platform text sizes is unverified.** Tiles size
  themselves from the preview-size preference rather than from the text metrics,
  so a large accessibility text size may clip a long window title.
- **Reduced-motion and increased-contrast settings are not specifically
  honoured.** The panels use the system material and standard SwiftUI controls,
  so they inherit whatever those do, but nothing here was tested against those
  settings.

`openswitchr-diag` emits plain text with no colour and no Unicode decoration, so
its output survives any pipe, log, or screen reader.

## Support and maintenance

Maintained by [@trsdn](https://github.com/trsdn) as a single-maintainer project,
best-effort and in the open. There is no service-level commitment and no
guaranteed response time.

- **Bugs and proposals** → [issues](https://github.com/trsdn/OpenSwitchr/issues),
  which offer a form for each. Please repeat a failing gesture twice before
  filing; several bugs here only appeared on the second attempt.
- **Security vulnerabilities** → report privately through
  [a security advisory](https://github.com/trsdn/OpenSwitchr/security/advisories/new),
  not a public issue.
- **Why the code is shaped the way it is** → `AGENTS.md`, which records the
  design constraints and the traps that produced them.

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
