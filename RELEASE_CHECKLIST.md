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

## Per release

1. Update `CHANGELOG.md`: move entries out of *Unreleased* into the new
   version, with the date.
2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
   The broker checks `CFBundleShortVersionString` against the tag and rejects a
   mismatch, and `CFBundleVersion` must be a numeric dotted version.
3. `swift build -Xswiftc -warnings-as-errors && swift test` — both must be
   clean. A warning in this project has repeatedly turned out to be a real bug,
   so it blocks the release.
4. `swift run openswitchr-diag --bench --capture` from a terminal that holds
   the Accessibility permission. Check that every accessibility window links to
   a CoreGraphics entry (`AX == LINKED` per app) and that the timings are still
   inside the budgets documented in `README.md`.
5. Merge to `main`, then tag `v<version>` and push the tag.
6. Request the notarized build from a checkout of the broker:

   ```bash
   scripts/request.sh openswitchr v<version>
   ```

   The broker verifies `provenance.json` and the release digests, and emits
   `OpenSwitchr-v<version>-macOS-arm64.dmg` with its `.sha256`.
7. Attach the broker's artifacts to the GitHub release. Do not upload anything
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
