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

## Updates and the broker

The app updates itself from GitHub Releases through
[AppUpdater](https://github.com/mxcl/AppUpdater) 4.1.2, pinned in `Package.swift`
with `Package.resolved` committed. **None of the following is done in this
repository, and until it is, no release can update an installed copy.**

1. **The release asset must be named exactly `OpenSwitchr-<semver>.dmg`.** AppUpdater
   accepts only that name, containing one app whose file name matches the
   installed one. On the broker profile that is an extra `copy_of` artifact of the
   notarized DMG (the broker emits `OpenSwitchr-v<version>-macOS-arm64.dmg`, which
   AppUpdater will not accept), and `scripts/request.sh openswitchr v<version>
   --publish` then uploads it.
2. **The broker profile needs a `dependency_lock`** equal to this repository's
   `Package.resolved`, and the compiled-in resource bundle
   `AppUpdater_AppUpdater.bundle` declared under `nested_resource_bundles`, the way
   the sibling apps' profiles do (trsdn/macos-notarization-broker#46).
3. **The signature must stay stable across updates.** Accessibility and Screen
   Recording grants are tied to the code signature, so a release signed with a
   different identity silently loses both.
4. **`THIRD_PARTY_NOTICES.txt` must be in the bundle.** `build-app.sh` copies it;
   the broker's adapter has to as well (AppUpdater is Unlicense, its dependency
   Version is Apache-2.0, whose terms ask for the license to travel).
5. **No `GitHubAttestationPolicy` is set.** The broker builds a release in its own
   repository, so there is no provenance from this one to verify, and for a
   `swift build` product AppUpdater's `Bundle.module` lookup never looks in
   `Contents/Resources`, so verifying one would end in a `fatalError`. The Developer
   ID, Team ID and bundle identifier checks still apply.

**Existing installs have no updater.** Anyone running a build from before this one
installs the first release that has it by hand.

**A real update has never been tested.** No release exists to update to. After
two releases, install the older on a Mac other than the build machine and confirm
the newer arrives and relaunches with its permissions intact.

## Localization and the broker

The interface is localized with String Catalogs that SwiftPM compiles into two
resource bundles, `OpenSwitchr_OpenSwitchr.bundle` (table `Localizable`) and
`OpenSwitchr_OpenSwitchrUI.bundle` (table `UI`), each holding `*.lproj`
directories. SwiftUI resolves strings against the app's **main** bundle, so the
`*.lproj` directories have to be copied into `Contents/Resources`, which is what
`scripts/build-app.sh` now does for local builds.

**The broker assembles the release bundle itself and does not do this yet.** Until
its `openswitchr-swiftpm` adapter copies the `*.lproj` directories from both
resource bundles into `Contents/Resources` (a reviewed pull request against
`profiles/apps.json` and the adapter, per the section above), a released build is
English-only while a local one is German on a German system. The two tables have
different names on purpose, so copying both merges rather than overwrites.

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
   `Localizable.stringsdict` and `UI.strings`. Absent means the broker still has
   not adopted the copy step above.
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
