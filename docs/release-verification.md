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
shasum -a 256 -c OpenSwitchr-X.Y.Z.dmg.sha256
hdiutil attach OpenSwitchr-X.Y.Z.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/OpenSwitchr/OpenSwitchr.app
codesign -dv /Volumes/OpenSwitchr/OpenSwitchr.app 2>&1 | grep TeamIdentifier   # G69Z5BNY97
spctl -a -t exec -vv /Volumes/OpenSwitchr/OpenSwitchr.app                       # Notarized Developer ID
xcrun stapler validate /Volumes/OpenSwitchr/OpenSwitchr.app
```

- The **Developer ID signature** ties the app to Apple Team `G69Z5BNY97`, and
  Apple's **notarization** ties it to a scan Apple ran. Both are verified by macOS
  itself on first launch, and the in-app updater refuses an update whose Team ID,
  signing identifier or bundle identifier differ from the running app's.
- **`provenance.json`** names the source repository, the source commit, the tag and
  its object, the broker commit and run id that built it, and the SHA-256 of every
  artifact.

What this does **not** prove: `provenance.json` is a file attached to the release,
not a signed GitHub Artifact Attestation, so it says where the build claims to have
come from without letting a consumer verify that claim cryptographically. The
signature proves who signed the app, not which commit it was built from.

## What the pipeline guarantees (`R03`, `R07`)

A tag does not start the build; a maintainer runs `scripts/request.sh openswitchr
vX.Y.Z` from a broker checkout. The broker builds from the tag's pinned commit
(refusing if the tag moved), signs, notarizes and, with `--publish`, creates the
release. **It refuses to publish when `CHANGELOG.md` has no entry for the version,
and uses that entry as the release notes**, so the notes on the Releases page are
the maintained changelog entry. It titles the release with the tag.

## Smoke tests of published artifacts (`R05`)

One record per release line. A later release that changes how the artifact is
built, signed or packaged needs a new one.

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
