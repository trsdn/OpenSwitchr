#!/usr/bin/env bash
# Smoke kit for a published release (criterion R05). Takes the file a consumer
# downloads, checks it, and starts it, without anyone operating the product.
#
#   scripts/smoke-release.sh [vX.Y.Z]     default: the latest release
#   OPENSWITCHR_SMOKE_NO_LAUNCH=1 ...     skip the start (signature checks only)
#   OPENSWITCHR_SMOKE_WAIT=1 ...          wait for the release files to appear
#
# Needs `gh` (authenticated for a private repo; a public one works anonymously in
# CI through GH_TOKEN). Exit code 0 means every check passed.
set -euo pipefail

REPO="${OPENSWITCHR_REPO:-trsdn/OpenSwitchr}"
TEAM_ID="G69Z5BNY97"
TAG="${1:-$(gh release view -R "$REPO" --json tagName --jq .tagName)}"
VERSION="${TAG#v}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/openswitchr-smoke.XXXXXX")"
# A real, symlink-free path: the updater refuses an app whose path has a symlink.
WORK="$(cd "$WORK" && pwd -P)"
MOUNT="$WORK/mount"
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

echo "Smoke test of $REPO $TAG"
# The release is created before its files are uploaded, so a run triggered by the
# release event may have to wait for them (OPENSWITCHR_SMOKE_WAIT=1).
attempts=1
[[ "${OPENSWITCHR_SMOKE_WAIT:-}" == "1" ]] && attempts=40
for attempt in $(seq 1 "$attempts"); do
    if gh release download "$TAG" -R "$REPO" -p "OpenSwitchr-$VERSION.dmg" -p "OpenSwitchr-$VERSION.dmg.sha256" -D "$WORK" 2>/dev/null; then
        break
    fi
    [[ "$attempt" == "$attempts" ]] && fail "could not download the release files for $TAG"
    sleep 15
done
( cd "$WORK" && shasum -a 256 -c "OpenSwitchr-$VERSION.dmg.sha256" >/dev/null ) || fail "checksum mismatch"
ok "checksum matches"

mkdir "$MOUNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$WORK/OpenSwitchr-$VERSION.dmg" >/dev/null
APP="$MOUNT/OpenSwitchr.app"
[[ -d "$APP" ]] || fail "the disk image holds no OpenSwitchr.app"

codesign --verify --deep --strict "$APP" 2>/dev/null || fail "codesign verification failed"
ok "signature valid"
DETAILS="$(codesign -dv "$APP" 2>&1)"
grep -q "TeamIdentifier=$TEAM_ID" <<<"$DETAILS" || fail "Team ID is not $TEAM_ID"
ok "signed by Team $TEAM_ID"
spctl -a -t exec "$APP" 2>/dev/null || fail "Gatekeeper rejects the app"
ok "Gatekeeper accepts it"
xcrun stapler validate "$APP" >/dev/null 2>&1 || fail "notarization ticket is not stapled"
ok "notarization ticket stapled"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true; }
[[ "$(plist CFBundleShortVersionString)" == "$VERSION" ]] || fail "bundle version is $(plist CFBundleShortVersionString), expected $VERSION"
ok "bundle version is $VERSION"
[[ "$(plist CFBundleIconFile)" == "AppIcon" && -f "$APP/Contents/Resources/AppIcon.icns" ]] || fail "the app icon is missing"
ok "app icon present"
for required in de.lproj/Localizable.strings de.lproj/UI.strings THIRD_PARTY_NOTICES.txt LICENSE; do
    [[ -e "$APP/Contents/Resources/$required" ]] || fail "missing Contents/Resources/$required"
done
ok "German localization and notices present"

if [[ "${OPENSWITCHR_SMOKE_NO_LAUNCH:-}" == "1" ]]; then
    echo "skipped: start (OPENSWITCHR_SMOKE_NO_LAUNCH=1)"
else
    cp -R "$APP" "$WORK/OpenSwitchr.app"
    xattr -cr "$WORK/OpenSwitchr.app" 2>/dev/null || true
    open -n "$WORK/OpenSwitchr.app"
    RUNNING=""
    for _ in $(seq 1 20); do
        RUNNING="$(pgrep -f "$WORK/OpenSwitchr.app/Contents/MacOS/OpenSwitchr" | head -1 || true)"
        [[ -n "$RUNNING" ]] && break
        sleep 1
    done
    [[ -n "$RUNNING" ]] || fail "the app did not start"
    sleep 3
    kill -0 "$RUNNING" 2>/dev/null || fail "the app started and then exited"
    ok "the app starts and keeps running"
    kill "$RUNNING" 2>/dev/null || true
fi
echo "PASS: $TAG"
