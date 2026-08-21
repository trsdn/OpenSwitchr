# Release checklist

OpenSwitchr ships as a Developer ID signed, notarized DMG for Apple Silicon.

## One-time setup

1. A **Developer ID Application** certificate must be in the login keychain.
   `security find-identity -v -p codesigning` has to list one; an *Apple
   Development* certificate is not enough for distribution, because Gatekeeper
   rejects it on other machines.
2. Create an app-specific password at <https://appleid.apple.com> and store a
   notary profile so the password never lands in a shell history or a file:

   ```bash
   xcrun notarytool store-credentials openswitchr-notary \
     --apple-id <apple-id> --team-id <team-id>
   ```

3. Optionally put non-secret overrides in `.release.env` (git-ignored):

   ```sh
   NOTARY_PROFILE=openswitchr-notary
   OPENSWITCHR_SIGNING_IDENTITY=<40-char fingerprint>
   ```

## Per release

1. Update `CHANGELOG.md`: move entries out of *Unreleased* into the new
   version, with the date.
2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
3. `swift build -Xswiftc -warnings-as-errors && swift test` — both must be
   clean. A warning in this project has repeatedly turned out to be a real
   bug, so it blocks the release.
4. `swift run openswitchr-diag --bench --capture` from a terminal that holds
   the Accessibility permission. Check that every accessibility window links
   to a CoreGraphics entry (`AX == LINKED` per app) and that the timings are
   still inside the budgets documented in `README.md`.
5. `bash scripts/release_macos.sh v<version>`.
6. Commit, tag `v<version>`, push the tag. The `Release macOS` workflow
   rebuilds, notarizes and attaches the assets.

## Verifying what you are about to publish

Notarization is easy to *believe* has happened, so check it explicitly rather
than trusting that the script printed something:

```bash
xcrun stapler validate dist/OpenSwitchr-v<version>-macOS-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 \
  dist/OpenSwitchr-v<version>-macOS-arm64.dmg
shasum -a 256 -c dist/OpenSwitchr-v<version>-macOS-arm64.dmg.sha256
```

Then mount the DMG, drag the app to `/Applications`, and confirm on a machine
that has never run it that it starts without a Gatekeeper warning.

## Without Apple credentials

`scripts/release_macos.sh` still produces a signed, checksummed DMG when no
notary credentials are configured; it skips notarization and the ZIP and says
so. That artifact is fine for local testing but **must not be published** —
users would hit a Gatekeeper block on first launch.

## After a rename

The bundle identifier is part of every TCC grant. If it ever changes again,
old grants for the previous identifier stay behind in System Settings under
Privacy & Security, pointing at an app that no longer exists. Remove them so
users are not asked to trust two entries for one app.

`tccutil reset Accessibility <old-bundle-id>` does **not** help here: once the
old bundle is gone from disk, LaunchServices can no longer resolve the
identifier and `tccutil` fails with OSStatus -10814. The leftover rows have to
be removed by hand with the `-` button in System Settings, so it is worth
doing the reset *before* deleting the old app bundle.
