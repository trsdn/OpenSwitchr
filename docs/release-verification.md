# Release verification and smoke tests

This is the record the quality standard's `R05`, `R07` and `R08` ask for. It says
what a consumer can check about a published release, what the release pipeline
guarantees, and what has actually been tested against a published artifact.

## What a consumer can check (`R08`)

OpenSwitchr releases are built, signed and notarized by
[`trsdn/macos-notarization-broker`](https://github.com/trsdn/macos-notarization-broker),
a shared pipeline, not by a workflow in this repository. Every release carries
`provenance.json`, and the app itself can be checked with the tools macOS ships:

```bash
gh attestation verify OpenSwitchr-X.Y.Z.dmg --repo trsdn/macos-notarization-broker
shasum -a 256 -c OpenSwitchr-X.Y.Z.dmg.sha256
hdiutil attach OpenSwitchr-X.Y.Z.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/OpenSwitchr/OpenSwitchr.app
codesign -dv /Volumes/OpenSwitchr/OpenSwitchr.app 2>&1 | grep TeamIdentifier   # G69Z5BNY97
spctl -a -t exec -vv /Volumes/OpenSwitchr/OpenSwitchr.app                       # Notarized Developer ID
xcrun stapler validate /Volumes/OpenSwitchr/OpenSwitchr.app
```

- The **build attestation** (releases after 0.2.2) is a statement GitHub signed with the
  broker workflow's own identity: this file's SHA-256 was produced by
  `notarize.yml` in `trsdn/macos-notarization-broker` at the recorded broker commit. It
  is verified with the first command above, which needs the GitHub CLI; a file changed by
  even one byte no longer matches.
- The **Developer ID signature** ties the app to Apple Team `G69Z5BNY97`, and
  Apple's **notarization** ties it to a scan Apple ran. Both are verified by macOS
  itself on first launch, and the in-app updater refuses an update whose Team ID,
  signing identifier or bundle identifier differ from the running app's.
- **`provenance.json`** names the source repository, the source commit, the tag and
  its object, the broker commit and run id that built it, and the SHA-256 of every
  artifact.

What this does **not** prove: the attestation names the broker workflow and commit, not
the source commit that was built. That is in `provenance.json`, which is data attached to
the release and not itself signed, so the source commit is a claim a consumer can read but
not cryptographically verify. Releases up to 0.2.2 have no attestation, because it was
added after them (a test run on 2026-09-21 verified with `gh attestation verify`: the
signed digest equalled the file's SHA-256, and a copy with one byte appended was rejected).
The signature proves who signed the app, not which commit it was built from.

## What the pipeline guarantees (`R03`, `R07`)

A tag does not start the build; a maintainer runs `scripts/request.sh openswitchr
vX.Y.Z` from a broker checkout. The broker builds from the tag's pinned commit
(refusing if the tag moved), signs, notarizes and, with `--publish`, creates the
release. **It refuses to publish when `CHANGELOG.md` has no entry for the version,
and uses that entry as the release notes**, so the notes on the Releases page are
the maintained changelog entry. It titles the release with the tag.

## Smoke tests of published artifacts (`R05`)

**The smoke kit** is `scripts/smoke-release.sh [vX.Y.Z]`. It takes the published disk
image, verifies its checksum, mounts it, checks the signature, the Team ID, Gatekeeper
and the stapled notarization ticket, checks that the bundle carries the release's version,
the app icon, the German localization and the notices, then starts the app from a copy and
confirms it keeps running. It needs no operator; exit code 0 means every check passed, and
`OPENSWITCHR_SMOKE_NO_LAUNCH=1` skips the start. It fails on v0.2.0 and v0.2.1, which had no
icon, so it catches the failure that shipped. `.github/workflows/smoke-release.yml` runs it on
a macOS runner whenever a release is published, which is the strongest form: every release
is checked without anyone remembering to.

Below are the dated runs, plus the tests done by hand before the kit existed.

### v0.2.2, 2026-09-20 (smoke kit)

`scripts/smoke-release.sh v0.2.2` run by an agent on the maintainer's Mac: all checks
passed, including the start. The same kit run against v0.2.1 and v0.2.0 fails on the missing
icon, as it should.

### v0.2.2, 2026-09-20 (by hand)

Found by inspecting the installed v0.2.1 bundle after the maintainer saw a generic app
icon: `AppIcon.icns` and `CFBundleIconFile` were missing from v0.2.0 and v0.2.1, because the
broker adapter never copied them (fixed in macos-notarization-broker#64, and the app's
build script now requires the icon).

Tested the published `OpenSwitchr-0.2.2.dmg`: `codesign --verify --deep --strict`, `spctl`
(Notarized Developer ID) and `stapler validate` pass, the bundle holds `AppIcon.icns` and
names it in the plist, and `de.lproj` is present.

Exercised on the maintainer's Mac, on the real installation in `/Applications`: the running
v0.2.1 found v0.2.2 through *Nach Updates suchen …*, downloaded it, installed it and
relaunched as 0.2.2 with the same Team ID, and its menu now starts with "OpenSwitchr 0.2.2".
Not exercised: a clean machine.

### v0.2.1, 2026-09-19

Tested the published files, not a local build: downloaded `OpenSwitchr-0.2.1.dmg`
from the GitHub release, mounted it and checked `codesign --verify --deep --strict`,
`spctl` (accepted, Notarized Developer ID) and `stapler validate` (worked).

Exercised on a real Mac:

- Installed v0.2.0 from its published DMG, chose *Check for Updates…*, and let the
  in-app updater download and install v0.2.1. The app relaunched as 0.2.1 with the
  same Team ID and a valid signature.
- On 0.2.1: the German menu and Settings window (all tabs), the About page showing
  0.2.1, and `de.lproj` present in the bundle.

Not exercised: a clean machine that has never run OpenSwitchr, and the hotkey and
Dock hover paths of the installed artifact. The test was done on the maintainer's
Mac, where Accessibility and Screen Recording were already granted. Also learned:
the updater refuses an app whose path contains a symlink, such as one run from
`/tmp`.
