#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PLUGIN_DIR="plugin"
MANIFEST="plugin/.claude-plugin/plugin.json"

# Claude Code keeps an installed plugin by its version number, and Hats offers a plugin update
# only when that number changes. So a release that changed plugin/ under the old number reaches
# nobody: v0.3.0 to v0.4.1 changed the plugin nine times and the number stayed 0.1.0.

versionIn() {
    python3 -I -c 'import json, sys
value = json.load(sys.stdin).get("version")
if not isinstance(value, str) or not value.strip():
    sys.exit(1)
print(value.strip())'
}

# The last release is the highest v* tag by version, not the nearest one: a release tag sits on
# a merge commit of main, which develop never contains, so the nearest tag reachable from a
# develop commit is an older release. And sorted as text, v0.9.0 comes after v0.10.0.
lastTag="$(git tag --list 'v*' --sort=-v:refname | head -n 1)"

if [[ -z "$lastTag" ]]; then
    if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
        echo "plugin-version-check: this checkout is shallow and has no v* tag, so the last release" >&2
        echo "                      is unknown and plugin/ was NOT checked. Fetch the history and the" >&2
        echo "                      tags (actions/checkout with fetch-depth: 0)." >&2
        exit 1
    fi
    echo "plugin-version-check: no v* tag yet, so there is no release to compare plugin/ with"
    exit 0
fi

# Against the working tree, not HEAD: an uncommitted change is what the package is about to
# carry, the same reason changelog-check reads the version the build is about to stamp.
if git diff --quiet "$lastTag" -- "$PLUGIN_DIR"; then
    echo "plugin-version-check: plugin/ has not changed since $lastTag"
    exit 0
fi

if [[ ! -f "$MANIFEST" ]]; then
    echo "plugin-version-check: plugin/ changed since $lastTag, and $MANIFEST is missing" >&2
    exit 1
fi
if ! current="$(versionIn < "$MANIFEST" 2>/dev/null)"; then
    echo "plugin-version-check: plugin/ changed since $lastTag, and $MANIFEST has no readable" >&2
    echo "                      \"version\" string" >&2
    exit 1
fi

# A manifest that did not exist at the tag means the plugin is new in this release, so any
# number it carries is new to its users.
if ! git cat-file -e "$lastTag:$MANIFEST" 2>/dev/null; then
    echo "plugin-version-check: $MANIFEST did not exist at $lastTag; the plugin is new, version $current"
    exit 0
fi
if ! released="$(git show "$lastTag:$MANIFEST" | versionIn 2>/dev/null)"; then
    echo "plugin-version-check: $MANIFEST at $lastTag has no readable \"version\" string, so the" >&2
    echo "                      released number is unknown" >&2
    exit 1
fi

if [[ "$current" == "$released" ]]; then
    echo "plugin-version-check: plugin/ changed since $lastTag, but \"version\" in $MANIFEST is" >&2
    echo "                      still $released." >&2
    echo "" >&2
    echo "Claude Code keeps an installed plugin by this number, and Hats offers a plugin update" >&2
    echo "only when it changes, so the change would reach nobody. Raise \"version\" in" >&2
    echo "$MANIFEST before the release. What changed:" >&2
    echo "  git diff --stat $lastTag -- $PLUGIN_DIR" >&2
    exit 1
fi

echo "plugin-version-check: plugin/ changed since $lastTag, version $released -> $current"
