# Self-assessment

Evidence for `.github/conformance.yml`. Assessed against version **1.15.0** of
the [trsdn Repository Quality Standard](https://github.com/trsdn/.github/blob/main/docs/repository-quality-standard.md)
on **2026-09-20**. Overall state: **Healthy**: no criterion fails, and the one
that is `partial` (`B13`) is a minor gap named below.

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

### 1.5.1 → 1.11.1

This reassessment is a version catch-up, not a response to a change in the
repository: `main` carries no commits between the 1.5.1 assessment
(2026-08-30) and this one beyond a dependency bump still pending as an open
pull request. Every `pass`, `partial`, and `fail` carried over from the
previous record was re-verified against the GitHub API and the tree rather
than assumed, and none of them moved.

`trsdn/.github`'s `main` branch has moved to an unreleased 1.12.0 — it adds
one further criterion, `W09` — but the reusable conformance workflow resolves
the standard at its published tag, and `v1.12.0` does not exist yet (the
latest tag is `v1.11.1`). This assessment is therefore against `v1.11.1`, the
version the workflow can actually check out; `W09` will be assessed once a
`v1.12.0` tag exists.

The standard grew by ten criteria between 1.5.1 and 1.11.1: `B14`-`B16`,
`P10`, `P11`, `R07`, `R08`, and `S11`-`S13`. Assessing those against this
repository for the first time surfaced one real, previously unrecorded gap:
`actions/checkout` and the reusable conformance workflow were pinned to
mutable refs (`S12`), fixed in the same change that added this reassessment
and recorded under Notable passes below.

### 1.11.1 → 1.13.0

Two changes to the standard, and a lot of work in the repository, moved results.

- **The standard widened** `R01`, `R03`, `R05`, `R07` and `R08` for repositories
  that release through a shared pipeline (this repository releases through the
  notarization broker). Those were the criteria that failed or were partial *because
  of that arrangement*, not because anything was missing. 1.12.0 retired `W05` and
  `W06` (the mandatory design language) and added `W09`, assessed under Notable passes.
- **The repository moved**: releases v0.2.0 and v0.2.1 exist and were tested; the
  activity card and badges are generated (`P09`, `P08`); the string catalogs are
  checked for orphans (`L04`); Swift formatting is enforced (`S03`); the display
  accessibility settings are honoured (`X03`); and the release path is covered in CI
  (`S02`). Each is under Notable passes.

### 1.13.0 → 1.15.0

The standard now states each criterion's Pass, Partial, Fail and Not applicable
boundaries and how an agent decides, and computes the overall state from the results
(`Healthy` when nothing fails). Re-reading every changed criterion against this
repository moved four results, in both directions:

- `R05` needs a **smoke kit**: a documented command that checks the published artifact
  without an operator, run by an agent. `scripts/smoke-release.sh` is that kit, and
  `.github/workflows/smoke-release.yml` runs it on every published release.
- `B13` moved **down**, from pass to partial: the standard now counts any
  hand-maintained restatement of a command, a version or runtime, or a policy, even one
  that agrees with its home. This repository has some (see `B13` below).
- `S02` moved up, from partial to pass, under the new definition of the main entry point
  for a graphical application (the logic behind the action, reached without its views).
- `S13` is `na`: no workflow uses `pull_request_target` or `workflow_run`, which is what
  `scripts/assess.py` decides from the workflow files.

The site also changed to meet `W03` and `W08` as now worded (see Notable passes).

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
| Published Sites | Yes | `docs/index.html`, served by GitHub Pages at [trsdn.github.io/OpenSwitchr](https://trsdn.github.io/OpenSwitchr/) |
| Archived | No | Actively developed |

## Partials

### `B13` — each fact has one home

**Partial.** The standard counts three kinds of fact in the README, `AGENTS.md`, the
contributing guide and `docs/`: a command, a version or supported runtime, and a policy.
A hand-maintained restatement that agrees with its home is a `Partial`; one that
disagrees is a `Fail`. Nothing here disagrees, but some restatements remain: the build
command appears in the README, `AGENTS.md` and on the site; the minimum macOS version is
written in the README, the site and `Info.plist` (the badge and `scripts/check.sh` tie
the last two to `Package.swift`); and the release command appears in the README and the
release checklist. The duplicated prose that used to disagree was merged into one home
each (the check.sh description, the shared-foundation rationale, the name), and links are
used where a fact's home is another file. What would make this a pass is deleting the
remaining restatements or generating them, which would make the README harder to read on
its own, so the gap is recorded rather than closed.

## Results that are `na`, and why

- **`D01`–`D06`** — nothing is deployed. There is no environment, no runtime
  infrastructure, and no operational surface. The app runs on a user's machine.
- **`T01`–`T05`** — the product is an application, not documentation. The
  documentation here supports the software rather than being the deliverable.
- **`S06`** — there is no runtime configuration. No environment variable, no
  configuration file, no remote configuration; only user preferences in
  `UserDefaults`, which are the user's own data rather than deployment config.
- **`L05`** — the interface formats no dates, numbers, currency, or sorted
  lists. The only numerals a user sees are in fixed option labels such as
  "At most every 5 s", which are static strings rather than formatted values,
  so there is no locale-sensitive formatting to get right or wrong.
- **`S13`** — no workflow here uses `pull_request_target` or `workflow_run`, so no
  workflow can be triggered by an untrusted contribution with access to a secret (and
  none references a `secrets.*` context at all).
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
- **`Y02`–`Y06`** — the app's one network connection is the daily update check to
  GitHub, documented with its destination and purpose in the README's Privacy
  section and Settings, and switched off by "Check for Updates Automatically";
  it has no telemetry, sends nothing to any other third party or AI provider, keeps thumbnails in memory under a
  byte budget so nothing outlives the session, and stores only preferences,
  whose location and deletion command are documented. `Y01` is the load-bearing
  one: the README states the "none" case explicitly, because "no privacy policy"
  and "no data collection" look identical from the outside.
- **`B14`** — this repository holds no Apple credential and says so more than
  once: `AGENTS.md` states plainly that Apple credentials must never be added
  here and that releases exist specifically so that never has to happen, and
  `.release.env.example` documents that the one identity string a local build
  uses is a Keychain selector, not a secret, gitignored regardless.
- **`B15`** — the app now redistributes two third-party packages, compiled in:
  AppUpdater 4.1.2 (Unlicense) and its dependency Version 2.2.1 (Apache-2.0).
  `THIRD_PARTY_NOTICES.txt` carries both licenses verbatim, names the pinned
  versions, and `scripts/build-app.sh` copies it into `Contents/Resources`. Both are
  pinned in `Package.swift` and `Package.resolved`. Version has no NOTICE file.
- **`B16`** — verified against the rulesets API directly: `main` carries both a
  `deletion` rule and a `non_fast_forward` rule with no exempted actor.
- **`P10`, `P11`** — the bug-report form asks for what happened, reproduction
  steps, the affected surface, version, macOS version and hardware, and
  permission state; the pull-request template (inherited from `trsdn/.github`)
  covers the summary, the related issue, validation, and risk.
- **`S11`** — every workflow in `.github/workflows` declares its permissions, and
  all but one are `contents: read`. The exception is `stats.yml`, whose one job has
  `contents: write` because generating the `P09` card needs it; it can only reach
  the generated `repo-stats` branch, and `AGENTS.md` records it as the single
  allowed exception. Verified by reading every workflow file.
- **`P09`** — the activity card is generated by `stats.yml` (the shared `repo-stats`
  workflow, pinned to a commit SHA, on a daily schedule) and committed to a
  generated `repo-stats` branch, with light and dark variants selected by a
  `<picture>` element in the README. It goes to a branch rather than `main` because
  the `main` ruleset requires pull requests and the workflow token cannot push
  there, which is the arrangement `docs/repo-stats.md` in the standard describes for
  protected branches. The card is served from `raw.githubusercontent.com` for this
  repository, not from a third-party image service. Caveat: a branch that only a
  workflow writes is not reviewed the way a pull request is.
- **`I06`** — identity metadata produced by the build. The bundle's version is not
  typed into `Info.plist` any more: the source plist holds a `__VERSION__` placeholder,
  `scripts/build-app.sh` fills it from the newest release heading in `CHANGELOG.md`
  (and verifies the built bundle carries that version), and the broker fills it from
  the resolved release tag, as its sibling adapters already did. `scripts/check.sh`
  fails if a version is typed into the source plist (mutation-tested), and CI builds
  the bundle on both runners. Verified by running the real broker adapter on this
  tree: it stamped the requested version and the result passed `validate_app_tree`.
  The changelog heading is still written by hand, which is the release act itself.
- **`R01`** — package metadata. SwiftPM has no field for a licence, a repository URL
  or a description, so under `R01` as of 1.13.0 they live in the artifact's own
  metadata: `Info.plist` carries the product name, both version strings, the repository
  and issue-tracker URLs, the licence identifier and the copyright holder, and
  `scripts/check.sh` asserts every one of those keys. `Package.swift` carries none of
  it, by the limits of the format.
- **`R03`** — a tag produces installable artifacts through automation. The
  notarization broker builds from the tag's pinned commit (refusing if the tag moved),
  signs, notarizes and publishes, without any Apple credential reaching this
  repository. A maintainer starts it for a specific tag with `scripts/request.sh`,
  documented in the README; v0.2.0 and v0.2.1 were produced that way. As of 1.13.0 a
  shared pipeline run for a tag qualifies.
- **`R04`** — tag, package version and release title agree. For v0.2.1 the tag,
  `CFBundleShortVersionString` and `CFBundleVersion`, the newest `CHANGELOG.md`
  heading and the GitHub Release title are all `0.2.1`. `scripts/check.sh` fails in CI
  when the plist and changelog disagree, and the broker now titles releases with the
  tag (macos-notarization-broker#62).
- **`R05`** — built artifacts smoke-tested. `scripts/smoke-release.sh` is the smoke kit: it
  downloads the published disk image, verifies its checksum, signature, Team ID,
  Gatekeeper acceptance and stapled ticket, checks the bundle for its version, icon,
  German localization and notices, and starts the app from a copy. It needs no operator.
  It ran on the maintainer's Mac and on a clean macOS runner against v0.2.2 (all passed),
  and it fails on v0.2.1 and v0.2.0, which shipped without the icon. The workflow
  `smoke-release.yml` runs it whenever a release is published, the strongest form under
  1.15.0. Dated runs and what was exercised by hand are in `docs/release-verification.md`.
- **`R06`** — release notes. `CHANGELOG.md` follows Keep a Changelog, and the broker
  publishes the entry for the tag as the release notes, so the Releases page carries
  the maintained entry, including upgrade-relevant items (v0.2.1 says 0.2.0 shipped
  without German and why).
- **`R07`** — release notes come from the changelog, gated. The gate is in the shared
  pipeline: the broker refuses `--publish` for a tag whose version has no entry in the
  source repository's `CHANGELOG.md` (macos-notarization-broker#53), and uses that
  entry as the notes. `docs/release-verification.md` documents this, and
  `## [Unreleased]` is empty, so no entry can be stranded. As of 1.13.0 a documented
  shared-pipeline gate qualifies.
- **`R08`** — a consumer can verify origin. `docs/release-verification.md` gives the
  commands (`shasum`, `codesign`, `spctl`, `stapler`) and says what they establish:
  the Developer ID signature (Team `G69Z5BNY97`) and Apple's notarization, plus
  `provenance.json` naming the source commit, the tag and the broker run. It also says
  what they do not: `provenance.json` is an attached file, not a signed GitHub
  Artifact Attestation. As of 1.13.0 the shared pipeline's verifiable record is
  sufficient evidence of origin.
- **`S02`** — automated test coverage. 241 tests in 28 suites cover the logic behind the
  app's main action, choosing a window: matching, most-recently-used ordering, filters
  and per-app rules, selection, thumbnail retention and capture limiting, panel lifecycle
  and placement, budgets and update scheduling, reached without any view. Failure paths
  are asserted (rejected input, undecodable rules, empty and filtered states, a lock that
  differs). CI runs them on two runners and builds the bundle unsigned, and the smoke kit
  covers the published file. Limit: the event tap, ScreenCaptureKit and the views are
  covered only by `openswitchr-diag`, which is run by hand.
- **`P08`** — status badges. The licence, minimum-macOS and release badges are
  generated by `scripts/badges.py` in `stats.yml` and committed to the generated
  `repo-stats` branch; the CI badge is GitHub's own and the conformance badge is
  committed from the record. Nothing in the README loads from a third-party image
  host any more, and the README's Privacy section says so.
- **`S03`** — static analysis. `swift build -Xswiftc -warnings-as-errors` and
  `swift format lint --strict` (config in `.swift-format`) run in `scripts/check.sh`
  and on both CI runners, and Markdown is linted against the standard's own config. The
  formatter is checked, never run, by the gate, and the fix command is in its message.
- **`L04`** — catalogs kept complete. `LocalizationCatalogTests` fails on a missing or
  incomplete German value and, since 2026-09-19, on an *orphaned* entry that no code
  refers to. The orphan test was mutation-tested: an injected dead key is reported by
  name. Interpolated literals are matched with each format specifier standing for the
  interpolation, which is generous by design.
- **`L06`** — traceability. Each entry is keyed by its English source string, so the
  source is traceable by construction. The origin is stated in the README's Language
  section as translation notes: machine-translated by a large language model from the
  English strings, not reviewed by a native speaker, with the date.
- **`X01`** — keyboard operability. The switcher is fully keyboard-driven, and the
  Dock preview's function, choosing among one application's windows, is reachable
  without a pointer through the second hotkey (the switcher scoped to the current
  application), which is documented in the README. The hover itself is a pointer
  gesture on a pointer-native system surface, the Dock, and gives no window the
  keyboard cannot also reach. This is a pass, not a not-applicable: the criterion
  applies to this app and is met.
- **`X03`** — contrast, motion and colour. The panels honour Reduce Motion, Reduce
  Transparency and Increase Contrast through `AccessibilityAppearance` (pure, tested;
  with every setting off the panels draw exactly as before). Meaning never rests on
  colour alone. macOS has no system text size that reaches third-party apps: a render
  at the largest SwiftUI text size came out identical to the default, so there is no
  enlarged-text mode to clip. Verified by unit tests and by rendering the high-contrast
  appearance; **not** verified by toggling the real system settings on a live desktop.
- **`S12`** — was a fail as of the first pass of this reassessment:
  `actions/checkout@v4` (later `@v7` via #29) and the reusable conformance
  workflow pinned to `trsdn/.github/...@main` could both change underneath
  this repository without a commit here. Both are now pinned to a full commit
  SHA, with a trailing comment naming the tag for readability — the pattern
  GitHub itself recommends for third-party actions.

- **`W09`** — the site's design is made for this project. Assessed by looking at the
  published page in light and dark and at phone width, not by a checklist. The palette
  (the icon's blue on paper or ink), the stacked-window motif, the app icon in the
  hero and the switcher panel (the app's own `SwitcherView`, rendered offscreen) all come from the
  product; the stylesheet, `docs/assets/site.css`, is hand-written for this one page
  and replaced the vendored framework. Focus is visible, contrast is set per theme,
  and at 390 px the page has no horizontal overflow (measured: `scrollWidth` 390).
  Limits: the panel is a render with invented sample windows and synthetic previews,
  captioned as such, not a screenshot of a real desktop, and the page has not been
  audited with a screen reader.
- **`W01`–`W08`** — the published site. It is one page, `docs/index.html`,
  served by GitHub's branch build from `main` / `docs` (`.nojekyll` disables the
  Jekyll pass so the markdown beside it is not rendered as pages).
  - `W01` — the process is repeatable and documented in `AGENTS.md`: merge to
    `main`. There is deliberately **no deployment workflow**: publishing from a
    workflow needs `pages: write` and an environment, which this repository does
    not allow itself (`AGENTS.md`, forbidden operations). The branch build is the
    same result without granting that.
  - `W02` — the repository `homepage` field is the site, and the site's footer
    and header link back to the repository.
  - `W03`, `W04` — the first visible content, at the standard's 1280×800 reference viewport,
    states what it is, who it is for (anyone who works across many windows), and its
    status ("early, actively developed", with "this page describes the latest
    release" linking to it), followed by how to get it, the one-sentence `Y01` disclosure, the repository,
    license, security policy and support links, and a last-reviewed date.
  - `W05`, `W06` — retired in 1.12.0, when the shared design language stopped being
    required. The site no longer uses it (see `W09`).
  - `W07` — network review, done by reading the page and its one stylesheet
    rather than trusting the claim: `docs/index.html` references no host other
    than `github.com` links a visitor has to click, and `docs/assets/site.css`
    contains no `http`, `@import` or `url()` reference. No script, no font
    request (system font stack), no cookie, no analytics.
  - `W08` — one page. The features it summarises link to their full list in the README,
    the install steps to the README's build section and the verification guide, and the
    privacy statement to the README's Privacy section, so a repeated fact always links
    to its home. Nothing addressed to contributors lives on it.
  The site is also a shipped interface, so accessibility applies to it: the page
  is semantic HTML with a skip link, a `lang` attribute, alt text on the
  picture (whose caption says it is a render with sample windows), and no
  script. It has not been audited with a screen reader.

## What to do next

In order of how much each one moves:

1. **Close `B13`** by deleting or generating the remaining restatements of the build
   command, the minimum macOS version and the release command.
2. **A GitHub Artifact Attestation** would turn the `provenance.json` claim into something
   a consumer can verify cryptographically. It needs `id-token: write` and
   `attestations: write` in the broker's `notarize.yml`, which the broker's own rules
   forbid, so it is a decision about the broker's trust boundary, not a task. `R08` passes
   without it under 1.14.0's statement rule.
