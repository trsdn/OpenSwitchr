#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${RELEASE_ENV_FILE:-$PROJECT_DIR/.release.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

# Local test packaging only. Distributable DMGs come from the notarization
# broker, which builds and packages with its own code; see RELEASE_CHECKLIST.md.
APP_NAME="OpenSwitchr"
APP_PATH="${APP_PATH:-$PROJECT_DIR/.build/release/$APP_NAME.app}"
DIST_DIR="$PROJECT_DIR/dist"
DMG_PATH="${DMG_PATH:-$DIST_DIR/OpenSwitchr-macos.dmg}"
STAGING_DIR="$PROJECT_DIR/.build/dmg-staging-$$-${RANDOM}"

cleanup() {
  rm -rf -- "$STAGING_DIR"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found at $APP_PATH" >&2
  echo "Run scripts/build-app.sh first." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f -- "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$(dirname "$DMG_PATH")"
mkdir -p "$STAGING_DIR"

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

identity="${CODE_SIGN_IDENTITY:-${OPENSWITCHR_SIGNING_IDENTITY:-}}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/' || true)"
fi

if [[ -z "$identity" ]]; then
  echo "No Developer ID Application identity found for DMG signing." >&2
  exit 1
fi

codesign --force --sign "$identity" --timestamp "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"

(
  cd "$(dirname "$DMG_PATH")"
  dmg_name="$(basename "$DMG_PATH")"
  shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
  shasum -a 256 -c "$dmg_name.sha256"
)

echo "DMG created: $DMG_PATH"
echo "This is a local test artifact and is not notarized. Do not publish it." 
