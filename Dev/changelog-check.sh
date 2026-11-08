#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PLIST_SOURCE="Build/build-app.sh"
CHANGELOG="CHANGELOG.md"

versionInAPlistSource() {
    sed -n '/CFBundleShortVersionString/{n;s|.*<string>\(.*\)</string>.*|\1|p;}'
}

# The version the build is about to stamp comes FIRST and from the working tree, not from
# history. Reading only committed history let an uncommitted bump ship with no entry: the
# gate said "all described" for a 0.8.0 build while the newest heading was 0.7.2. What the
# bundle will report is what the file says now; history covers what it has ever reported.
versionsEverReported() {
    versionInAPlistSource < "$PLIST_SOURCE"
    if resolvesToACommit; then
        git rev-list HEAD -- "$PLIST_SOURCE" 2>/dev/null | while read -r sha; do
            git show "$sha:./$PLIST_SOURCE" 2>/dev/null | versionInAPlistSource
        done
    fi
}

# A .git directory is not a resolvable HEAD. In a checkout with no commits `rev-parse
# --git-dir` succeeds and `rev-list HEAD` then dies at 128, which under set -e killed the
# script with git's own stderr instead of the diagnostic below.
resolvesToACommit() {
    git rev-parse --verify --quiet HEAD >/dev/null 2>&1
}

if [[ ! -f "$CHANGELOG" ]]; then
    echo "changelog-check: $CHANGELOG is missing" >&2
    exit 1
fi

if ! resolvesToACommit; then
    echo "changelog-check: no resolvable HEAD here, so only the version $PLIST_SOURCE stamps now" >&2
    echo "                 is checked and the versions ever reported before were NOT." >&2
fi

versions="$(versionsEverReported | awk 'NF && !seen[$0]++')"

if [[ -z "$versions" ]]; then
    echo "changelog-check: no version could be read out of the history of $PLIST_SOURCE, so" >&2
    echo "                 $CHANGELOG was NOT checked against it." >&2
    exit 0
fi

# No version is excused. The private line (0.2.0 to 0.9.0, never published) once had a
# list here that skipped its numbers, but the public repository's history starts at 0.1.0
# and never carried them, while public releases reuse the same numbers: on 2026-11-08 the
# list silenced the checks for the published 0.2.0, 0.3.0 and the new 0.4.0.
missing=""
while read -r version; do
    [[ -n "$version" ]] || continue
    if ! grep -qE "^## ${version//./\\.}([[:space:]]|$)" "$CHANGELOG"; then
        missing="$missing $version"
    fi
done <<< "$versions"

if [[ -n "$missing" ]]; then
    echo "changelog-check: $CHANGELOG has no entry for:$missing" >&2
    echo "" >&2
    echo "Every version the bundle has ever reported needs a heading of the form" >&2
    echo "  ## <version> — <date>" >&2
    echo "because the app shows this file to the person installing it, and a version" >&2
    echo "missing from it reads as a version that changed nothing." >&2
    exit 1
fi

echo "changelog-check: $(echo "$versions" | wc -l | tr -d ' ') versions ever reported, all described"
