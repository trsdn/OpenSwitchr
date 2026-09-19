# OpenSwitchr

[![License: MIT](https://img.shields.io/github/license/trsdn/OpenSwitchr?label=license)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)](#requirements)
[![CI](https://github.com/trsdn/OpenSwitchr/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/trsdn/OpenSwitchr/actions/workflows/ci.yml)
[![Latest tag](https://img.shields.io/github/v/tag/trsdn/OpenSwitchr?label=release)](https://github.com/trsdn/OpenSwitchr/releases)
[![Conformance](.github/badges/conformance.svg)](.github/conformance.yml)

**One app instead of two.** Dock hover previews and a hold-and-Tab window
switcher, built on a single shared window index.

macOS ships with `⌘-Tab`, which switches *applications*, not *windows*. The
usual way to close that gap is to run two separate utilities: one that previews
an application's windows when you hover its Dock icon, and one that puts a
visual switcher on screen. They solve two halves of the same problem, and each
pays the full cost of doing so on its own — enumerating every window, observing
every change, capturing every thumbnail. Running both means paying twice.

OpenSwitchr pays once. The window index, the event bus, the thumbnail cache, and
the window actions exist exactly once; the Dock previews and the switcher
overlay are thin readers on top.

---

## Features

- **Switcher overlay** — hold `⌘` and press `Tab` for every window on the
  current Space in most-recently-used order, with live thumbnails. `⌥` and `⌃`
  are available in Settings if you would rather keep the system switcher.
- **A second hotkey, off by default** — the same modifier with `` ` `` opens the
  switcher for the current application's windows only, and keeps every other list
  setting you chose. It is one toggle, not a second copy of the settings, and it
  replaces the macOS shortcut for cycling an application's own windows.
- **Type to filter** — start typing to narrow by app name or window title.
- **Choose what the switcher lists** — by application, by display, how
  minimized windows are treated, and in what order.
- **Applications with no windows, off by default** — list running applications
  that have every window closed, after the windows, so you can switch to them.
  Choosing one activates it and asks it to open a window, as a Dock click does.
- **Icons instead of previews** — pick icons and titles only in Settings, or
  let it happen on its own when Screen Recording is not granted or a panel has
  more than twelve windows. Icon mode captures nothing.
- **Dock hover previews** — hover a Dock icon to see that app's windows; click
  one to jump straight to it. The open delay applies to the first preview only,
  so moving along the Dock does not wait again.
- **Scroll to cycle, off by default** — with the pointer on a Dock icon, scrolling
  focuses that application's next or previous window without opening a preview.
  It listens to scrolling only while the pointer is on a Dock icon.
- **Window actions** — focus, minimize, restore, and close from either frontend.
- **Minimized windows included** — a window in the Dock is still listed, dimmed
  and marked, and activating its tile restores it.
- **Menu bar app** — no Dock icon, no window of its own.

## Status

Early, and actively developed. The core is implemented and measured, `v0.1.0`
is tagged, and releases run through the notarization broker. There is no
published binary yet, so installing means building from source. There is a
[project page](https://trsdn.github.io/OpenSwitchr/) for readers who want the
product rather than the source.

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

The **Apps** tab edits the per-application rules: for each bundle identifier
prefix, hide its windows (never, always, or when the title contains some text)
and stand aside while it is frontmost and full screen, so a remote desktop,
screen share or virtual machine gets the switcher hotkey itself. Each hiding rule
shows how many windows it removes right now, so a rule that empties the switcher
is noticed where it was set. The rules are stored as one JSON value under the
`appRules` key; deleting that key restores the shipped defaults.

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
swift run openswitchr-diag --check-budgets    # timings against budgets; exits 1 if exceeded
swift run openswitchr-diag --filters          # filter profiles against real windows
swift run openswitchr-diag --probe-app        # drive the *installed* app
```

`--check-budgets` turns the measured numbers into thresholds that can fail. It is
a pre-release check, not a CI gate: the measurements need the Accessibility grant,
real windows, and a machine that is not sharing a core with other jobs, and a
wall-clock budget on someone else's laptop is noise. The budgets live in one file,
`Sources/openswitchr-diag/Budgets.swift`, and are raised only in the commit that
justifies it.

It reports per-app `CG` / `AX` / `LINKED` counts, which separates "the linking
heuristic failed" from "this app exposes no accessibility windows at all".

`--filters` exists for the one filter axis unit tests cannot judge. Restricting
the switcher to one display compares a window frame from CoreGraphics against a
screen frame AppKit measures in the opposite vertical direction, and a wrong
flip still looks correct on a single display because the two spaces coincide
there. The mode applies the scope to every attached display and then asserts
the thing that actually matters: no window may end up claimed by none of them.

`--probe-app` is the only check that exercises the shipping app rather than the
core: it posts a synthetic hotkey, measures how long the overlay takes to
appear, **holds the modifier for four seconds to prove the overlay stays**,
moves the pointer onto the Dock mid-hold to prove a preview appearing beside it
does not take it away, confirms focus actually moved by reading the
CoreGraphics z-order, then hovers a Dock icon *twice* and times both previews.
The core passing its tests says nothing about whether the app wired it up —
two release-blocking bugs got through exactly that gap.

The two hold checks exist because the probe used to press and release within
250 ms, so an overlay that appears and then gives up on its own passed every
check it had.

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

Hovering the Dock icon of an application with no windows shows **no panel**. A
panel announcing "no windows" is one the user has to get past to reach the icon
underneath, and it would appear precisely when they were reaching for a click.
It also could not be truthful: the index only describes the current Space, so an
application whose only window is on another Space looks exactly like one with no
windows, and the honest answer to both is "nothing here", not a claim. The Dock
click is unaffected.

## What the switcher shows

Both frontends read the same index, but they do not want the same set, so each
carries a filter profile. The Dock preview's is fixed and permissive — the
pointer already picked the application, so any further restriction could only
hide something you pointed at. The switcher's is yours:

| Axis | Default | Options |
|---|---|---|
| Show | All applications | All, only the current application, or everything but the current application |
| Minimized windows | Show | Show, hide, or show after the rest |
| Displays | All displays | All, or only the display the switcher appears on |
| Order | Most recently used | Most recently used, most recently opened, or application then title |

The defaults are exactly what the app did before the setting existed, so
changing nothing changes nothing.

Two details that are easy to get wrong and are therefore pinned by tests. A
minimized window is on no display at all, so restricting to one display never
removes it — otherwise a display setting would quietly delete every window in
the Dock. And "show after the rest" is a partition applied after ordering, not
a tie-breaker inside the comparator, because the latter is not a strict weak
ordering and `sort` is free to misbehave with one.

"Most recently opened" is honest about its limits: windows that were already
open when the app launched are ordered back-to-front from z-order, because
nothing records when a window that predates the process was opened. The same
applies after a round trip to another Space: the index keeps bookkeeping only
for windows it can currently see, so a window that leaves and comes back looks
newly opened — the same way it already loses its place in the recently-used
order.

The switcher opens even when the filter matches nothing, and says so. It has to:
the hotkey is swallowed by the event tap either way, so returning early would
leave `⌘-Tab` doing nothing at all while the system switcher stayed suppressed,
with no clue why.

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

**English and German.** English is the primary language and the source of every
string. The interface is localized through two String Catalogs:
`Sources/OpenSwitchr/Localizable.xcstrings` for the app and
`Sources/OpenSwitchrUI/UI.xcstrings` for the shared views. The repository's
documents, the `openswitchr-diag` command-line output, commit messages and issues
stay English. The product name and the modifier symbols (⌘ ⌥ ⌃) are never
translated. Counts use plural forms rather than string interpolation.

Two things to know:

- **The German was written by an AI assistant and has not been reviewed by a
  native speaker.** Corrections are a catalog edit.
- **Only a locally built app is localized so far.** `scripts/build-app.sh` copies
  the compiled `.lproj` directories into the bundle, but the release broker
  assembles its own bundle and does not yet, so a released build is English until
  its `openswitchr-swiftpm` adapter does the same. See `RELEASE_CHECKLIST.md`.

A test reads the catalogs and the views and fails on an untranslated entry, a
translation that drops a placeholder, an incomplete plural, a lost product name,
or a new literal that never reached a catalog. Adding a language is a catalog
edit plus an entry in `CFBundleLocalizations` in `Info.plist`.

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
