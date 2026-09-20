#!/bin/bash
# The one command that validates a change before it is proposed.
#
# Everything here runs without a signing identity, without the Accessibility
# permission, and without a network connection, so it works the same on a
# laptop, in CI, and for an agent. The checks that *do* need real windows live
# in `openswitchr-diag` and are deliberately not run from here — see the
# "Verifying the app, not just the core" section of AGENTS.md.
#
#   bash scripts/check.sh
#   bash scripts/check.sh --metadata-only   # skip build and tests
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RUN_BUILD=true
case "${1:-}" in
    --metadata-only) RUN_BUILD=false ;;
    "") ;;
    *) echo "usage: $0 [--metadata-only]" >&2; exit 2 ;;
esac

failures=0

step() {
    printf '\n== %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

if [[ "$RUN_BUILD" == true ]]; then
    # Warnings are treated as failures: this project has repeatedly found real
    # bugs behind warnings, so a warning is a finding, not noise.
    step "Build (warnings are errors)"
    if swift build -Xswiftc -warnings-as-errors; then
        echo "ok"
    else
        fail "swift build"
    fi

    # Formatting is checked, never rewritten, here: a check that edits files would
    # make a passing run depend on what it changed. Fix with
    # `swift format -i --recursive Sources Tests`.
    step "Swift formatting"
    if swift format lint --strict --recursive Sources Tests; then
        echo "ok"
    else
        fail "swift format lint (run: swift format -i --recursive Sources Tests)"
    fi

    step "Tests"
    if swift test; then
        echo "ok"
    else
        fail "swift test"
    fi
fi

# The version has one home, the newest release heading in CHANGELOG.md; the build
# fills Info.plist from it (scripts/build-app.sh, and the broker from the tag). A
# version typed into Info.plist would be a second home that can drift, so the
# source plist must keep its placeholder. See criterion I06.
step "Version comes from the changelog"
plist_short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist 2>/dev/null || echo '')"
plist_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist 2>/dev/null || echo '')"
changelog_version="$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' CHANGELOG.md | head -1)"

echo "Info.plist CFBundleShortVersionString: ${plist_short:-<missing>}"
echo "Info.plist CFBundleVersion:            ${plist_build:-<missing>}"
echo "CHANGELOG.md newest release:           ${changelog_version:-<missing>}"

if [[ ! "$changelog_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "CHANGELOG.md has no release heading like '## [1.2.3]'"
elif [[ "$plist_short" != "__VERSION__" || "$plist_build" != "__VERSION__" ]]; then
    fail "Info.plist must keep __VERSION__; the build sets the version from CHANGELOG.md"
else
    echo "ok"
fi

# Identity keys the About tab reads back at runtime. A missing key degrades
# silently into a hidden link, which is exactly the kind of failure that ships.
step "Bundle identity keys"
for key in CFBundleName CFBundleIdentifier NSHumanReadableCopyright \
           OSWLicenseIdentifier OSWRepositoryURL OSWIssueTrackerURL; do
    if /usr/libexec/PlistBuddy -c "Print :$key" Info.plist >/dev/null 2>&1; then
        echo "ok   $key"
    else
        fail "Info.plist is missing $key"
    fi
done

# The minimum macOS version is stated in three places that no compiler compares:
# the package manifest, the bundle the build script writes, and the README badge
# a reader believes (generated from the manifest by scripts/badges.py). A hardcoded badge beside a manifest that has moved on is
# precisely the drift the badge convention exists to prevent.
step "Minimum macOS version agrees everywhere"
manifest_major="$(sed -n 's/.*\.macOS(\.v\([0-9][0-9]*\)).*/\1/p' Package.swift | head -1)"
bundle_major="$(sed -n "s/.*LSMinimumSystemVersion'\] = '\([0-9][0-9]*\)\..*/\1/p" scripts/build-app.sh | head -1)"
badge_major="$(python3 scripts/badges.py --print platform | sed -n 's/^macOS \([0-9][0-9]*\)+$/\1/p')"

echo "Package.swift platforms:               ${manifest_major:-<missing>}"
echo "build-app.sh LSMinimumSystemVersion:   ${bundle_major:-<missing>}"
echo "README badge (scripts/badges.py):        ${badge_major:-<missing>}"

if [[ -z "$manifest_major" || -z "$bundle_major" || -z "$badge_major" ]]; then
    fail "could not read the minimum macOS version from all three places"
elif [[ "$manifest_major" != "$bundle_major" || "$manifest_major" != "$badge_major" ]]; then
    fail "minimum macOS version disagrees: manifest $manifest_major, bundle $bundle_major, badge $badge_major"
else
    echo "ok"
fi

step "Badge generator"
if (cd scripts && python3 -m unittest test_badges -q); then
    echo "ok"
else
    fail "scripts/test_badges.py failed"
fi

# Documentation in this repository carries design rationale, so it is linted
# too. Skipped rather than failed when npx is unavailable, because the check
# must stay runnable offline. CI runs the same linter in its own workflow.
if [[ "$RUN_BUILD" == true ]]; then
    step "Markdown lint"
    if command -v npx >/dev/null 2>&1; then
        if npx --yes markdownlint-cli2@0.18.1 "**/*.md"; then
            echo "ok"
        else
            fail "markdownlint"
        fi
    else
        echo "skipped: npx not available"
    fi
fi

printf '\n'
if (( failures > 0 )); then
    echo "$failures check(s) failed." >&2
    exit 1
fi

echo "All checks passed."

if [[ "$RUN_BUILD" == true ]]; then
    echo
    echo "Not covered here, because no test can reach it: real accessibility"
    echo "linking rates, capture timings, and whether the installed app wired any"
    echo "of it up. Run 'swift run openswitchr-diag --bench --capture' and"
    echo "'swift run openswitchr-diag --probe-app' from a terminal that holds the"
    echo "Accessibility permission."
fi
