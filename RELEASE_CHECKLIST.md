# Release checklist

Distributable builds of OpenSwitchr are produced by
[`trsdn/macos-notarization-broker`](https://github.com/trsdn/macos-notarization-broker),
not by this repository.

## Why the broker owns the release

Apple credentials never reach this repository. The broker treats application
repositories as untrusted: it builds the app from a pinned commit in a job with
no secrets, validates and repackages the result on a second secretless runner,
and only then signs and notarizes with broker-owned code in a protected
environment.

The practical consequence is that **this repository does not define the release
bundle**. `scripts/build-app.sh` and `scripts/make_dmg.sh` exist for local
development and testing only; the broker assembles the bundle itself using its
`openswitchr-swiftpm` adapter. If the two ever disagree, the broker's preflight
rejects the release rather than signing something unexpected.

That also means a change to the bundle — identifier, executable name, layout,
architecture, entitlements, or minimum macOS version — is not a local decision.
It requires a reviewed pull request against the broker's `profiles/apps.json`,
and the release fails until that lands.

## Updates, localization and the broker

The app updates itself from GitHub Releases through
[AppUpdater](https://github.com/mxcl/AppUpdater) 4.1.2, pinned in `Package.swift`
with `Package.resolved` committed, and its interface is localized with String
Catalogs. The broker assembles the release bundle itself, so both depend on the
broker's `openswitchr` profile and `assemble_openswitchr` adapter.

**The broker side has landed**
([trsdn/macos-notarization-broker#56](https://github.com/trsdn/macos-notarization-broker/pull/56)):

- `locks/openswitchr-Package.resolved` is a byte-for-byte copy of this repository's
  `Package.resolved`, and the adapter requires the two to be equal before and after
  compilation. **The lock's `originHash` is tied to `Package.swift`, so any change to
  its dependency section needs the lock refreshed in the broker first.**
- The data-only `AppUpdater_AppUpdater.bundle` is declared and copied.
- `*.lproj` directories are copied out of OpenSwitchr's own resource bundles into
  `Contents/Resources` (those bundles are not shipped; the app resolves strings
  against its main bundle). The two string tables have different names, so they
  merge.
- `THIRD_PARTY_NOTICES.txt` and `LICENSE` are bundled.
- `OpenSwitchr-{version}.dmg` is published as a copy of the notarized DMG, the exact
  name AppUpdater accepts.
- No `GitHubAttestationPolicy` is set: the broker builds a release in its own
  repository, so there is no provenance from this one to verify, and for a
  `swift build` product AppUpdater's `Bundle.module` lookup never looks in
  `Contents/Resources`, so verifying one would end in a `fatalError`. The Developer
  ID, Team ID and bundle identifier checks still apply.

That was checked by running the real adapter, and then by real releases: v0.2.0 and
v0.2.1 were built, signed and notarized by the broker, and `docs/release-verification.md`
records what was verified about them and how to verify a download.

**What was learned, and stays true:**

1. **A release needs no manual approval.** The broker's `macos-signing` environment has
   no required reviewer, by design. What gates a release is the changelog: the broker
   refuses `--publish` without an entry for the version, and publishes that entry as the
   notes. To release: move the entries out of *Unreleased* into a new version heading
   (`Info.plist` needs no change), tag, and run `scripts/request.sh openswitchr
   v<version> --publish` from a broker checkout.
2. **The signature must stay stable across updates.** Accessibility and Screen
   Recording grants are tied to the code signature, so a release signed with a different
   identity silently loses both. v0.2.0 and v0.2.1 share Team ID `G69Z5BNY97` and the
   same designated requirement.
3. **Check the bundle, not the build log.** 0.2.0 shipped without German because the
   runner's SwiftPM copies string catalogs instead of compiling them. The broker now
   compiles them itself and refuses to ship without `de.lproj`, `build-app.sh` does the
   same, and CI builds the bundle on every run.
4. **The updater refuses an app whose path contains a symlink**, such as one run from
   `/tmp`; test an update from a normal folder.
5. **Builds from before 0.2.0 have no updater**, so anyone still running one installs a
   newer release by hand once.

Per release, after the broker's artifact exists:
`ls OpenSwitchr.app/Contents/Resources/de.lproj` should list `Localizable.strings`,
`Localizable.stringsdict` and `UI.strings`, and `THIRD_PARTY_NOTICES.txt` should sit
beside them. Absent means the broker profile regressed.

## Per release

1. Update `CHANGELOG.md`: move entries out of *Unreleased* into the new
   version, with the date.
2. Nothing to bump in `Info.plist`: it holds a `__VERSION__` placeholder that
   `scripts/build-app.sh` fills from the newest release heading in `CHANGELOG.md`
   and the broker fills from the tag. `scripts/check.sh` fails if a version is typed
   there. The broker still checks the built bundle against the tag.
3. `swift build -Xswiftc -warnings-as-errors && swift test` — both must be
   clean. A warning in this project has repeatedly turned out to be a real bug,
   so it blocks the release.
4. `swift run openswitchr-diag --check-budgets` from a terminal that holds the
   Accessibility and Screen Recording permissions, on a quiet machine. It exits
   non-zero when a budget in `Sources/openswitchr-diag/Budgets.swift` is
   exceeded or could not be measured. The budgets are wall-clock, so a failure
   on a busy machine is worth one re-run before it is worth believing; raising
   one is done in the commit that justifies it. Also run
   `swift run openswitchr-diag --bench --capture` and check that every
   accessibility window links to a CoreGraphics entry (`AX == LINKED` per app).
5. Merge to `main`, then tag `v<version>` and push the tag.
6. Request the notarized build from a checkout of the broker:

   ```bash
   scripts/request.sh openswitchr v<version>
   ```

   The broker verifies `provenance.json` and the release digests, and emits
   `OpenSwitchr-v<version>-macOS-arm64.dmg` with its `.sha256`.
7. Install the broker's artifact and confirm the localized resources are in it:
   `ls OpenSwitchr.app/Contents/Resources/de.lproj` should list `Localizable.strings`,
   `Localizable.stringsdict` and `UI.strings`. Absent means the broker
   profile regressed (see above).
8. Attach the broker's artifacts to the GitHub release. Do not upload anything
   built locally.

## Local testing

```bash
bash scripts/build-app.sh   # signed with whatever identity is on this machine
bash scripts/make_dmg.sh    # unnotarized DMG in dist/
```

Both are for testing on this machine. The DMG is signed but not notarized, so
publishing it would give users a Gatekeeper block on first launch.

## Verifying what you are about to publish

Notarization is easy to *believe* has happened, so check the broker's artifact
explicitly rather than trusting that a script printed something:

```bash
xcrun stapler validate OpenSwitchr-v<version>-macOS-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 \
  OpenSwitchr-v<version>-macOS-arm64.dmg
shasum -a 256 -c OpenSwitchr-v<version>-macOS-arm64.dmg.sha256
```

Then mount it, drag the app to `/Applications`, and confirm on a machine that
has never run it that it starts without a Gatekeeper warning.

## After a rename

The bundle identifier is part of every TCC grant. If it ever changes again,
old grants for the previous identifier stay behind in System Settings under
Privacy & Security, pointing at an app that no longer exists. Remove them so
users are not asked to trust two entries for one app. The broker's profile pins
the identifier, so a rename also needs a reviewed profile change.

`tccutil reset Accessibility <old-bundle-id>` does **not** help here: once the
old bundle is gone from disk, LaunchServices can no longer resolve the
identifier and `tccutil` fails with OSStatus -10814. The leftover rows have to
be removed by hand with the `-` button in System Settings, so it is worth doing
the reset *before* deleting the old app bundle.
