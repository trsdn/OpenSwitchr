#!/usr/bin/env bash
#
# Renames the product across the whole repository.
#
# "OpenSwitch" collides with the Linux Foundation's OpenSwitch (OPX) network
# operating system. Nothing has been published under this name yet, so the
# rename is cheap today and expensive later. This script keeps it a one-liner.
#
# Usage:
#   bash scripts/rename-product.sh OpenSwitchr
#   bash scripts/rename-product.sh OpenSwitchr com.openswitchr.app
#
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <NewName> [new.bundle.identifier]" >&2
    exit 1
fi

OLD_NAME="OpenSwitch"
OLD_BUNDLE_ID="com.openswitch.app"
NEW_NAME="$1"
NEW_BUNDLE_ID="${2:-com.$(echo "$NEW_NAME" | tr '[:upper:]' '[:lower:]').app}"

OLD_LOWER="$(echo "$OLD_NAME" | tr '[:upper:]' '[:lower:]')"
NEW_LOWER="$(echo "$NEW_NAME" | tr '[:upper:]' '[:lower:]')"
OLD_UPPER="$(echo "$OLD_NAME" | tr '[:lower:]' '[:upper:]')"
NEW_UPPER="$(echo "$NEW_NAME" | tr '[:lower:]' '[:upper:]')"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty. Commit or stash first so the rename is reviewable." >&2
    exit 1
fi

echo "Renaming $OLD_NAME -> $NEW_NAME (bundle id $NEW_BUNDLE_ID)"

# Rename directories and files before rewriting their contents, so the
# subsequent content pass sees the final layout.
[[ -d "Sources/$OLD_NAME" ]] && git mv "Sources/$OLD_NAME" "Sources/$NEW_NAME"
[[ -d "Sources/${OLD_NAME}Core" ]] && git mv "Sources/${OLD_NAME}Core" "Sources/${NEW_NAME}Core"
[[ -d "Sources/${OLD_NAME}UI" ]] && git mv "Sources/${OLD_NAME}UI" "Sources/${NEW_NAME}UI"
[[ -d "Sources/${OLD_LOWER}-diag" ]] && git mv "Sources/${OLD_LOWER}-diag" "Sources/${NEW_LOWER}-diag"
[[ -d "Tests/${OLD_NAME}CoreTests" ]] && git mv "Tests/${OLD_NAME}CoreTests" "Tests/${NEW_NAME}CoreTests"
[[ -f "$OLD_NAME.entitlements" ]] && git mv "$OLD_NAME.entitlements" "$NEW_NAME.entitlements"

# The bundle identifier must be replaced before the bare product name, since it
# contains the lowercased name as a substring.
FILES=$(git ls-files -- '*.swift' '*.plist' '*.sh' '*.md' '*.yml' '*.yaml' '*.entitlements' '*.example' 'Package.swift')

for file in $FILES; do
    [[ -f "$file" ]] || continue
    perl -pi -e "
        s/\Q$OLD_BUNDLE_ID\E/$NEW_BUNDLE_ID/g;
        s/\Q$OLD_NAME\E/$NEW_NAME/g;
        s/\Q$OLD_LOWER\E/$NEW_LOWER/g;
        s/\Q$OLD_UPPER\E/$NEW_UPPER/g;
    " "$file"
done

echo ""
echo "Done. Review with: git diff"
echo "Then verify:       swift build && swift test && bash scripts/build-app.sh"
echo ""
echo "Remaining manual steps:"
echo "  - Rename the GitHub repository and update remotes."
echo "  - Remove the stale TCC grants for $OLD_BUNDLE_ID in System Settings."
echo "  - Update docs/ and any published download links."
