# Self-assessment

Evidence for `.github/conformance.yml`. Assessed against version **1.5.1** of
the [trsdn Repository Quality Standard](https://github.com/trsdn/.github/blob/main/docs/repository-quality-standard.md)
on **2026-08-30**. Overall state: **Needs work** — two criteria fail, both for
reasons named below, and the repository is otherwise usable and honest about
itself.

Every line here is evidence from the GitHub API, a workflow run, a measurement,
or a file in the tree. Nothing is assumed. Where a result is `partial` or
`fail`, the entry says what was observed and what would have to change.

## What changed since the previous assessment

The previous assessment was recorded inline in `AGENTS.md`, against standard
version 1.3.3, and it had gone stale. It opened by reporting that the default
branch held two files — `README.md` and `.gitignore` — with everything else
living in an unmerged branch. That was true when it was written and stopped
being true when pull request #1 merged, which invalidated roughly a dozen
results at once, including the licence findings that it called the highest
priority item in the repository.

That failure is the reason `B13` exists and the reason this document is now
separate from `AGENTS.md`: a fact with two homes has no home. It is also why
the record is validated by a scheduled workflow rather than by memory.

## Profiles

| Profile | Applies | Why |
| --- | --- | --- |
| Baseline | Yes | Always |
| Public | Yes | Public visibility |
| Software | Yes | Ships a Swift package and an app bundle |
| Product Identity | Yes | Builds a signed `.app` a user installs |
| Package And Release | Yes | Releases run through the notarization broker |
| Agent Readiness | Yes | `AGENTS.md` exists and agents work here |
| Language And Localization | Yes | A shipping user interface |
| Accessibility | Yes | A shipping user interface |
| Data Protection And Privacy | Yes | Reads window metadata and captures screen content |
| Deployable | No | Nothing is deployed to any environment |
| Documentation | No | The product is software; docs support it |
| Published Sites | No | There is no site. The homepage points at the releases page |
| Archived | No | Actively developed |

## Failures

### `P09` — repository activity card

**Fail, and deliberately so.** The criterion requires an activity card
generated from an authoritative source and committed to the repository, so no
third-party rendering service observes readers. The shared implementation is the
reusable `repo-stats` workflow, which commits the rendered SVG back to the
repository and therefore needs `contents: write`.

`AGENTS.md` forbids exactly that: *"no workflow here may use a secret, an
environment, or write permissions."* That rule is what makes this repository
safe to build from without reviewing every workflow, and it is not worth trading
for a statistics card.

The two are genuinely in conflict, so this is recorded as a fail rather than
argued into a pass. Resolving it needs either a generation path that does not
write to the repository, or an explicit decision to relax the workflow rule.

### `R05` — built artifacts smoke-tested in a clean environment

**Fail.** `openswitchr-diag --probe-app` is a real end-to-end check — it posts a
synthetic hotkey, times the overlay against a window-ID baseline, confirms focus
moved by reading the CoreGraphics z-order, and hovers a Dock icon twice — but it
runs against the app installed on the development machine, where the toolchain,
the permissions, and the previously granted TCC entries all already exist.

Nothing yet takes a notarized artifact, installs it somewhere that has never
seen it, and confirms it launches and is trusted by Gatekeeper. The most likely
failure that hides here is a signing or notarization problem, which is invisible
locally by construction: the local machine trusts its own developer certificate.

## Partials

### `B13` — each fact has one home

`README.md` and `AGENTS.md` still overlap. Both describe the shared-index
architecture, both tell the `⌘-Tab` story, and both state the current-Space
scope. The audiences differ — one is for a user deciding whether to install, the
other for someone changing the code — but the same fact is written twice in
places, and the two can drift.

Moving the conformance assessment out of `AGENTS.md` removed the worst instance.
The remaining overlap is smaller and has not yet caused a contradiction.

### `P08` — status badges

The required five badges are present, in the required order, and each links to
what it reports. Values are not hand-maintained:

| Badge | Where the value comes from |
| --- | --- |
| License | GitHub's own licence detection for this repository |
| macOS 15+ | Hardcoded, but `scripts/check.sh` fails when it disagrees with `Package.swift` or `scripts/build-app.sh` |
| CI | GitHub's first-party workflow badge for `main` |
| Latest tag | The repository's tags |
| Conformance | Rendered from `.github/conformance.yml` and committed as `.github/badges/conformance.svg`; the Conformance workflow fails when the two drift apart |

What keeps this at `partial` is the image host. The conformance badge is served
from this repository and the CI badge is first-party, but the licence, platform,
and tag badges are rendered by `img.shields.io`, and the standard asks for
images served from the repository or a first-party source *where practical*,
because a third-party image host observes every reader. Serving those three
from here would mean generating and committing more SVGs on a schedule, which
runs into the same write-permission conflict as `P09`.

The consequence is disclosed rather than hidden: the Privacy section of the
README names `img.shields.io` as the one host that viewing the README contacts,
and states that nothing in the app itself contacts it.

### `S02` — automated test coverage

48 tests across 6 suites, all pure logic: the AX-to-`CGWindowID` linker
including its tie-breaking and determinism, MRU ordering, the window matcher,
the thumbnail refresh-rate age limits, permission-grant watching, and focus
target resolution. They cover the parts where a subtle bug is invisible, and
several encode a bug that actually shipped.

They cannot cover anything that talks to another process or draws: accessibility
enumeration, ScreenCaptureKit, the event tap, and every SwiftUI view. That gap
is filled by `openswitchr-diag`, which is run by hand and is not in CI, because
it needs the Accessibility permission and real windows. Three release-blocking
bugs have gone through exactly that gap — the app never starting, settings that
could not be changed, and a Dock hover that worked only the first time — while
every test stayed green.

### `S03` — automated static analysis

`swift build -Xswiftc -warnings-as-errors` runs in CI on both runners, and this
project has repeatedly found real bugs behind warnings, so that is genuine
static analysis rather than a formality. Markdown is now linted in CI against
the same `.markdownlint.jsonc` the standard publishes.

No Swift formatter or linter is configured. There is no `swift-format`
configuration and no SwiftLint, so formatting is consistent only by habit.

### `R01` — package metadata

`Info.plist` now carries the product name, both version strings, the repository
URL, the issue tracker URL, the licence identifier, and the copyright holder,
and `scripts/check.sh` asserts every one of those keys is present.

`Package.swift` carries none of it, because SwiftPM has no field for a licence,
a repository, or a description. That is a limitation of the manifest format
rather than an omission, but the criterion asks for complete package metadata
and half of it lives somewhere SwiftPM cannot see.

### `R03` — a tag produces installable artifacts through automation

Automation exists and is real: `trsdn/macos-notarization-broker` builds from a
pinned commit, signs, and notarizes, without any Apple credential reaching this
repository. That is a better arrangement than a release workflow here would be.

It is not triggered by a tag. Someone runs `scripts/request.sh openswitchr
v0.1.0` from a broker checkout. Pushing a tag therefore publishes nothing on its
own, and a tag can exist with no artifact behind it — which is the state this
repository is in right now.

### `R04` — tag, package version, and release title agree

`v0.1.0` is tagged and pushed, and points at the current `main`. `Info.plist`
and `CHANGELOG.md` both say `0.1.0`, and `scripts/check.sh` now fails if those
two ever disagree.

No GitHub Release exists, so there is no release title to agree with anything,
and the tag has no artifact attached. Two of the three things the criterion
compares are present and consistent; the third has not been created.

### `R06` — release notes

`CHANGELOG.md` follows Keep a Changelog, states the versioning policy, and its
entries describe the measurement or the trap behind each change rather than
listing files. It is materially better than most release notes.

It has never been published as release notes, because no release exists.

### `I06` — identity metadata produced by the build

Still hand-maintained. `CFBundleVersion` and `CFBundleShortVersionString` are
typed into `Info.plist`; nothing derives them from the tag.

What changed is that drift is now loud rather than silent: `scripts/check.sh`
fails when the two plist versions disagree with each other or with the newest
release heading in `CHANGELOG.md`, and CI runs that check on both runners. The
standard accepts a check that fails on drift in place of derivation for badge
values, which is why this is a `partial` rather than a `fail`.

Deriving the version properly means changing how the bundle is produced, and
the release bundle is assembled by the broker's `openswitchr-swiftpm` adapter
rather than by `scripts/build-app.sh`. Doing it in only one of the two would
make them disagree, so this needs a broker-side change first.

### `X01` — keyboard operability

The switcher overlay is fully keyboard-driven: hold the modifier, `Tab` and
`⇧-Tab` move the selection, typing filters by app name or window title, `Escape`
cancels, releasing the modifier commits. The selection is visibly indicated.

Dock hover previews have no keyboard route at all. They are triggered by the
pointer entering a Dock icon, which is inherent to the gesture rather than an
oversight — but it does mean one of the two frontends is pointer-only. The
switcher reaches every window on the current Space without a pointer, so nothing
is unreachable; it is the Dock-adjacent workflow specifically that is not.

This is now stated in the Accessibility section of the README rather than left
for a user to discover.

### `X03` — contrast, text sizing, and colour

Meaning never rests on colour alone. The quit control on a preview tile is red
*and* a distinct glyph placed in the opposite corner from the close control, and
a minimized window is dimmed *and* explicitly marked.

Behaviour under enlarged platform text sizes is unverified. Tiles size
themselves from the preview-size preference rather than from text metrics, so a
large accessibility text size may clip a long window title. Reduced-motion and
increased-contrast settings are not specifically honoured either; the panels use
system materials and standard SwiftUI controls and inherit whatever those do.
Both limitations are stated in the README under `X05`.

## Results that are `na`, and why

- **`D01`–`D06`** — nothing is deployed. There is no environment, no runtime
  infrastructure, and no operational surface. The app runs on a user's machine.
- **`T01`–`T05`** — the product is an application, not documentation. The
  documentation here supports the software rather than being the deliverable.
- **`W01`–`W08`** — there is no published site. The repository homepage points
  at its own releases page, which is not a site in the sense the profile means.
- **`S06`** — there is no runtime configuration. No environment variable, no
  configuration file, no remote configuration; only user preferences in
  `UserDefaults`, which are the user's own data rather than deployment config.
- **`L04`, `L06`** — there are no string catalogs and no translations, so there
  is nothing to keep complete or to trace. English-only is declared under `L03`.
- **`L05`** — the interface formats no dates, numbers, currency, or sorted
  lists. The only numerals a user sees are in fixed option labels such as
  "At most every 5 s", which are static strings rather than formatted values,
  so there is no locale-sensitive formatting to get right or wrong.
- **`A01`–`A04`** — actively developed, not archived.

## Notable passes

These are recorded because they took work, not because they were free.

- **`B06`, `S09`** — `main` is protected by a ruleset: pull requests are
  required, the two CI matrix checks and the secret scan must pass, and force
  pushes and branch deletion are blocked. Verified against the rulesets API.
- **`S05`** — three independent layers. `secret-scan.yml` runs on every push and
  pull request, GitHub secret scanning is enabled, and push protection now
  rejects a credential before it reaches the remote.
- **`S07`** — verified by reading every logging call in the tree: no window
  title, no personal data, only counts, pids, and error descriptions. This is
  what makes it safe to ask a reporter to paste a log into an issue, which the
  bug report form does.
- **`S10`** — `AGENTS.md` records not just the architecture but the traps that
  produced it, including two long detours caused by a broken measurement rather
  than broken code.
- **`G03`, `G06`, `G07`** — forbidden operations, generated paths, and the
  review expectation are now written down. Previously an agent was expected to
  follow rules it had no way to read.
- **`G05`** — `scripts/check.sh` is one command that validates a change without
  a signing identity, permissions, or network access.
- **`I02`, `I03`, `I04`** — the bundle carries its repository URL, issue tracker
  URL, licence identifier, and copyright holder, ships the licence text in
  `Contents/Resources`, and the About tab renders its links by reading those
  keys back rather than hardcoding them a second time.
- **`X04`** — `openswitchr-diag` emits plain text with no colour and no Unicode
  decoration, so its output survives any pipe, log, or screen reader.
- **`Y02`–`Y06`** — the app opens no network connection, has no telemetry, sends
  nothing to any third party or AI provider, keeps thumbnails in memory under a
  byte budget so nothing outlives the session, and stores only preferences,
  whose location and deletion command are documented. `Y01` is the load-bearing
  one: the README states the "none" case explicitly, because "no privacy policy"
  and "no data collection" look identical from the outside.

## What to do next

In order of how much each one moves:

1. **Publish a GitHub Release for `v0.1.0`** with a notarized artifact from the
   broker. That is the single change that most improves the release profile,
   moving `R04` and `R06` and making `R05` testable at all.
2. **Smoke-test that artifact somewhere clean** — a machine or VM that has never
   run OpenSwitchr — and record the result. Clears `R05`.
3. **Decide the `P09` conflict deliberately**: either accept no activity card,
   or relax the no-write-permissions rule with a stated reason. Either is a
   defensible answer; leaving it undecided is not.
4. **Add a Swift formatter or linter** to close `S03`.
5. **Verify the app under enlarged accessibility text sizes** and either fix the
   clipping or keep the limitation documented. Moves `X03`.
6. **Resolve the version derivation** with the broker so `I06` stops depending
   on a human typing the same number in two files.
