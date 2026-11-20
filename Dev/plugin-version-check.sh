#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

MANIFEST="plugin/.claude-plugin/plugin.json"
SHIPPED=(plugin .claude-plugin/marketplace.json)
SHIPPED_NAMES="plugin/ or .claude-plugin/marketplace.json"

# Claude Code keeps an installed plugin by its version number, and Hats offers a plugin update
# only when that number changes. So a release that changed what ships with the plugin under the
# old number reaches nobody. The plugin first ships with the first release that contains
# plugin/; until such a tag exists, the check answers that the plugin is new.

versionIn() {
    python3 -I -c 'import json, sys
value = json.load(sys.stdin).get("version")
if not isinstance(value, str) or not value.strip():
    sys.exit(1)
print(value.strip())'
}

# The last release is the highest vN.N.N tag by version, not the nearest one: a release tag sits
# on a merge commit of main, which develop never contains, so the nearest tag reachable from a
# develop commit is an older release. Sorted as text, v0.9.0 comes after v0.10.0. A pre-release
# or any other v* name is not a release. A tag on HEAD itself is the release being made, and
# comparing it with itself would always pass, so the baseline is the one before it.
# A failing git tag is not read as "no tag": an empty answer would skip the comparison.
if ! onHead="$(git tag --points-at HEAD 2>&1)"; then
    echo "plugin-version-check: git tag --points-at HEAD failed:" >&2
    echo "$onHead" >&2
    exit 1
fi
if ! tags="$(git tag --list 'v*' --sort=-v:refname 2>&1)"; then
    echo "plugin-version-check: git tag --list failed:" >&2
    echo "$tags" >&2
    exit 1
fi
lastTag=""
while read -r tag; do
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    grep -Fqx -- "$tag" <<< "$onHead" && continue
    lastTag="$tag"
    break
done <<< "$tags"

if [[ -z "$lastTag" ]]; then
    if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
        echo "plugin-version-check: this checkout is shallow and has no release tag vN.N.N, so the" >&2
        echo "                      last release is unknown and plugin/ was NOT checked. Fetch the" >&2
        echo "                      history and the tags (actions/checkout with fetch-depth: 0)." >&2
        exit 1
    fi
    echo "plugin-version-check: no release tag vN.N.N yet, so there is no release to compare plugin/ with"
    exit 0
fi

# Against the working tree, not HEAD: an uncommitted change is what the package is about to
# carry, the same reason changelog-check reads the version the build is about to stamp. git diff
# does not see untracked files, so a new file is looked for separately. Exit 1 of git diff means
# "differs"; anything above it is git failing, and is not read as either answer.
DIFF_RC=0
DIFF_ERR="$(git diff --quiet "$lastTag" -- "${SHIPPED[@]}" 2>&1)" || DIFF_RC=$?
if (( DIFF_RC > 1 )); then
    echo "plugin-version-check: git diff against $lastTag failed (exit $DIFF_RC):" >&2
    echo "$DIFF_ERR" >&2
    exit 1
fi
if ! STATUS="$(git status --porcelain --untracked-files=all -- "${SHIPPED[@]}" 2>&1)"; then
    echo "plugin-version-check: git status failed:" >&2
    echo "$STATUS" >&2
    exit 1
fi
if (( DIFF_RC == 0 )) && ! grep -q '^??' <<< "$STATUS"; then
    echo "plugin-version-check: $SHIPPED_NAMES has not changed since $lastTag"
    exit 0
fi

if [[ ! -f "$MANIFEST" ]]; then
    echo "plugin-version-check: $SHIPPED_NAMES changed since $lastTag, and $MANIFEST is missing" >&2
    exit 1
fi
if ! current="$(versionIn < "$MANIFEST" 2>/dev/null)"; then
    echo "plugin-version-check: $SHIPPED_NAMES changed since $lastTag, and $MANIFEST has no" >&2
    echo "                      readable \"version\" string" >&2
    exit 1
fi

# A manifest that did not exist at the tag means the plugin is new in this release, so any
# number it carries is new to its users. ls-tree tells "absent" (empty output) from "git failed".
if ! AT_TAG="$(git ls-tree --name-only "$lastTag" -- "$MANIFEST" 2>&1)"; then
    echo "plugin-version-check: git ls-tree on $lastTag failed:" >&2
    echo "$AT_TAG" >&2
    exit 1
fi
if [[ -z "$AT_TAG" ]]; then
    echo "plugin-version-check: $MANIFEST did not exist at $lastTag; the plugin is new, version $current"
    exit 0
fi
if ! released="$(git show "$lastTag:$MANIFEST" | versionIn 2>/dev/null)"; then
    echo "plugin-version-check: $MANIFEST at $lastTag has no readable \"version\" string, so the" >&2
    echo "                      released number is unknown" >&2
    exit 1
fi

highest="$(printf '%s\n%s\n' "$released" "$current" | sort -V | tail -n 1)"
if [[ "$current" == "$released" || "$highest" != "$current" ]]; then
    echo "plugin-version-check: $SHIPPED_NAMES changed since $lastTag, but \"version\" in" >&2
    echo "                      $MANIFEST is $current, not above the released $released." >&2
    echo "" >&2
    echo "Claude Code keeps an installed plugin by this number, and Hats offers a plugin update" >&2
    echo "only when it rises, so the change would reach nobody. Raise \"version\" in" >&2
    echo "$MANIFEST before the release. What changed:" >&2
    echo "  git diff --stat $lastTag -- ${SHIPPED[*]}" >&2
    echo "  git status --short --untracked-files=all -- ${SHIPPED[*]}" >&2
    exit 1
fi

echo "plugin-version-check: $SHIPPED_NAMES changed since $lastTag, version $released -> $current"
