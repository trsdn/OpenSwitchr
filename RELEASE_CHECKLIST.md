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

That was checked by running the real adapter against a clean clone of this repository
with a real `swift build`, and the resulting tree passes the broker's `validate_app_tree`.
It was **not** checked by a real notarized release.

**What is still open, and cannot be done by a change to either repository:**

1. **No release with the updater exists.** `v0.1.0` predates it (it is well behind
   `main`), so releasing that tag would ship an app with no updater and no German. The
   first updater-capable release needs a new version: move the changelog entries out of
   *Unreleased*, bump `Info.plist` (`scripts/check.sh` fails if it disagrees with the
   changelog), tag, and run `scripts/request.sh openswitchr v<version> --publish` from a
   broker checkout. The signing job runs in a protected environment that needs a human
   approval.
2. **The signature must stay stable across updates.** Accessibility and Screen
   Recording grants are tied to the code signature, so a release signed with a different
   identity silently loses both.
3. **A real update has never been run.** After two releases, install the older on a Mac
   other than the build machine and confirm the newer arrives and relaunches with its
   permissions intact.
4. **Existing installs have no updater**, so anyone running a build from before this one
   installs the first updater-capable release by hand.

Per release, after the broker's artifact exists:
`ls OpenSwitchr.app/Contents/Resources/de.lproj` should list `Localizable.strings`,
`Localizable.stringsdict` and `UI.strings`, and `THIRD_PARTY_NOTICES.txt` should sit
beside them. Absent means the broker profile regressed.

## Per release

1. Update `CHANGELOG.md`: move entries out of *Unreleased* into the new
   version, with the date.
2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
   The broker checks `CFBundleShortVersionString` against the tag and rejects a
   mismatch, and `CFBundleVersion` must be a numeric dotted version.
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
