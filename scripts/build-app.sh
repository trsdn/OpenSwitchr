#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${RELEASE_ENV_FILE:-$PROJECT_DIR/.release.env}"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP="$BUILD_DIR/OpenSwitchr.app"
DEFAULT_BUNDLE_ID="com.openswitchr.app"
PREFERRED_IDENTITY="${OPENSWITCHR_SIGNING_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"

# --unsigned assembles the bundle without a signing identity. It exists so CI can
# exercise the whole packaging path, including localization, on a runner that holds
# no certificate. The result is not for distribution.
UNSIGNED=false
[[ "${1:-}" == "--unsigned" ]] && UNSIGNED=true

if [[ -f "$ENV_FILE" ]]; then
    set -a
    . "$ENV_FILE"
    set +a
    PREFERRED_IDENTITY="${OPENSWITCHR_SIGNING_IDENTITY:-${CODE_SIGN_IDENTITY:-$PREFERRED_IDENTITY}}"
fi

find_signing_identity() {
    if [[ -n "$PREFERRED_IDENTITY" ]]; then
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -v preferred="$PREFERRED_IDENTITY" '
                $2 == preferred || index($0, preferred) { print $2; found = 1; exit }
                END { if (!found) exit 1 }
            '
        return
    fi

    security find-identity -v -p codesigning 2>/dev/null \
        | awk '
            /Developer ID Application:/ { print $2; found = 1; exit }
            /Apple Development:/ && !apple_dev { apple_dev = $2 }
            END {
                if (found) {
                    exit 0
                } else if (apple_dev) {
                    print apple_dev
                } else {
                    exit 1
                }
            }
        '
}

SIGNING_IDENTITY=""
$UNSIGNED || SIGNING_IDENTITY="$(find_signing_identity || true)"

if ! $UNSIGNED && [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "No valid macOS codesigning identity found." >&2
    echo "Install a Developer ID Application or Apple Development certificate, or set OPENSWITCHR_SIGNING_IDENTITY to a valid fingerprint." >&2
    exit 1
fi

echo "Building OpenSwitchr..."
cd "$PROJECT_DIR"
swift build -c release

# Regenerated on every build so the icon can never fall behind the mark the
# menu bar draws from the same source.
echo "Rendering app icon..."
swift run -c release openswitchr-icon "$PROJECT_DIR"

echo "Creating app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/OpenSwitchr" "$APP/Contents/MacOS/OpenSwitchr"
cp "$PROJECT_DIR/Info.plist" "$APP/Contents/Info.plist"

# The version has one home: the newest release heading in CHANGELOG.md, which is
# also what the broker publishes as release notes. Info.plist carries a
# __VERSION__ placeholder that is filled in here (and by the broker, from the tag).
VERSION="$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' "$PROJECT_DIR/CHANGELOG.md" | head -1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "CHANGELOG.md has no release heading like '## [1.2.3]' to take the version from." >&2
    exit 1
}

# The licence travels with the artifact, not just with the repository: someone
# handed a .app has no checkout to read it from.
cp "$PROJECT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE"
# Compiled-in third-party code (AppUpdater, Version): their license terms travel
# with the app. See THIRD_PARTY_NOTICES.txt.
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.txt" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"

HAS_ICON=false
# Localized strings. SwiftUI resolves literals against the app's main bundle, so
# the compiled *.lproj directories have to sit in Contents/Resources. They are
# compiled here from the String Catalogs rather than copied out of SwiftPM's
# resource bundles, because whether SwiftPM compiles a catalog at all depends on
# its build backend: some toolchains only copy the raw .xcstrings, and the first
# localized release shipped English-only for exactly that reason. The release
# broker does the same (see RELEASE_CHECKLIST.md). Each module has its own table
# (Localizable, UI), so the outputs merge into one lproj.
while IFS= read -r catalog; do
    xcrun xcstringstool compile "$catalog" --output-directory "$APP/Contents/Resources"
done < <(find "$PROJECT_DIR/Sources" -name '*.xcstrings' -type f)

if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    HAS_ICON=true
fi

HAS_ICON="$HAS_ICON" VERSION="$VERSION" python3 -c "
import os, plistlib
app = '$APP'
with open(app + '/Contents/Info.plist', 'rb') as f:
    p = plistlib.load(f)
p['CFBundleShortVersionString'] = os.environ['VERSION']
p['CFBundleVersion'] = os.environ['VERSION']
p['CFBundleExecutable'] = 'OpenSwitchr'
p['CFBundlePackageType'] = 'APPL'
p['CFBundleDisplayName'] = 'OpenSwitchr'
p['NSHighResolutionCapable'] = True
p['LSMinimumSystemVersion'] = '15.0'
if os.environ['HAS_ICON'] == 'true':
    p['CFBundleIconFile'] = 'AppIcon'
with open(app + '/Contents/Info.plist', 'wb') as f:
    plistlib.dump(p, f)
"

# A bundle that lacks its localization or notices is a broken release even when it
# launches, so the build checks its own output instead of trusting the copy steps.
for required in de.lproj/Localizable.strings de.lproj/UI.strings THIRD_PARTY_NOTICES.txt LICENSE; do
    [[ -e "$APP/Contents/Resources/$required" ]] || {
        echo "Bundle is missing Contents/Resources/$required" >&2
        exit 1
    }
done

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || {
    echo "Bundle version is $BUILT_VERSION, expected $VERSION from CHANGELOG.md" >&2
    exit 1
}

if $UNSIGNED; then
    echo "App bundle created at: $APP (unsigned, not for distribution)"
    exit 0
fi

# Sign with a stable, trusted identity so TCC permissions survive rebuilds.
codesign --force --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    --identifier "$DEFAULT_BUNDLE_ID" \
    --entitlements "$PROJECT_DIR/OpenSwitchr.entitlements" \
    "$APP"

SIGNATURE_DETAILS=$(codesign -dv "$APP" 2>&1)
if echo "$SIGNATURE_DETAILS" | grep -qi 'Signature=adhoc'; then
    echo "codesign produced an ad-hoc signature; aborting so macOS permissions do not reset." >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP"

echo "App bundle created at: $APP"
echo "Signed with identity: $SIGNING_IDENTITY"
echo "Size: $(du -sh "$APP" | cut -f1)"
echo ""
echo "To install:  cp -R \"$APP\" /Applications/"
echo "To run:      open /Applications/OpenSwitchr.app"
