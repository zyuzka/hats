#!/usr/bin/env bash
# Checks plugin-version-check.sh on made-up repositories: each case builds a temporary git
# repository with a plugin/ folder and v* tags, copies the script into its Dev/ and runs it there.
#
# Run it from the repository root: bash Dev/plugin-version-check.test.sh — prints one line per failure and exits
# non-zero if there are any. It touches no repository but the temporary ones.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/plugin-version-check.sh"

failures=0
cases=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1

g() {
    git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false \
        -c tag.gpgsign=false -c init.defaultBranch=main "$@"
}

newRepo() {
    local repo="$work/$1"
    mkdir -p "$repo/Dev"
    g -C "$repo" init -q
    cp "$script" "$repo/Dev/plugin-version-check.sh"
    printf 'tooling\n' > "$repo/README"
    g -C "$repo" add README
    g -C "$repo" commit -q -m base
    printf '%s\n' "$repo"
}

manifest() {
    local repo="$1" version="$2"
    mkdir -p "$repo/plugin/.claude-plugin"
    printf '{\n  "name": "hats",\n  "version": "%s"\n}\n' "$version" > "$repo/plugin/.claude-plugin/plugin.json"
}

pluginFile() {
    local repo="$1" text="$2"
    mkdir -p "$repo/plugin/hooks"
    printf '%s\n' "$text" > "$repo/plugin/hooks/hook.sh"
}

moveOn() {
    printf 'more\n' >> "$1/README"
    commitAll "$1" "outside plugin"
}

commitAll() {
    g -C "$1" add -A
    g -C "$1" commit -q -m "$2"
}

expect() {
    local name="$1" repo="$2" want="$3" needle="${4:-}"
    local out rc
    cases=$((cases + 1))
    out="$(bash "$repo/Dev/plugin-version-check.sh" 2>&1)"
    rc=$?
    if [[ "$rc" != "$want" ]]; then
        echo "FAIL $name: exit $rc, expected $want; output:"
        printf '  %s\n' "$out"
        failures=$((failures + 1))
        return
    fi
    if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
        echo "FAIL $name: output lacks \"$needle\"; output:"
        printf '  %s\n' "$out"
        failures=$((failures + 1))
    fi
}

r="$(newRepo no-tag)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
expect "no v* tag" "$r" 0 "no release tag vN.N.N yet"

r="$(newRepo unchanged)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
printf 'more\n' >> "$r/README"; commitAll "$r" "outside plugin"
expect "plugin unchanged since the tag" "$r" 0 "has not changed since v1.0.0"

r="$(newRepo changed-same)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
pluginFile "$r" b; commitAll "$r" "plugin change"
expect "committed change, same version" "$r" 1 "is 1.0.0, not above the released 1.0.0"

r="$(newRepo changed-raised)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
pluginFile "$r" b; manifest "$r" 1.0.1; commitAll "$r" "plugin change and bump"
expect "committed change, raised version" "$r" 0 "version 1.0.0 -> 1.0.1"

r="$(newRepo uncommitted)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
pluginFile "$r" b
expect "uncommitted change, same version" "$r" 1 "is 1.0.0, not above the released 1.0.0"

r="$(newRepo uncommitted-raise)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
pluginFile "$r" b; commitAll "$r" "plugin change"
manifest "$r" 1.0.1
expect "committed change, version raised in the working tree" "$r" 0 "1.0.0 -> 1.0.1"

r="$(newRepo version-order)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v0.9.0
pluginFile "$r" b; commitAll "$r" "plugin change, released as v0.10.0"
g -C "$r" tag v0.10.0
moveOn "$r"
expect "highest tag by version, not by text" "$r" 0 "has not changed since v0.10.0"

r="$(newRepo unreachable-tag)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" checkout -q -b release
pluginFile "$r" b; commitAll "$r" "release"
g -C "$r" tag v2.0.0
g -C "$r" checkout -q main
expect "tag on a commit the branch does not contain" "$r" 1 "changed since v2.0.0"

r="$(newRepo other-tags)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
pluginFile "$r" b; commitAll "$r" "plugin change"
g -C "$r" tag release-9
expect "tags not starting with v are ignored" "$r" 1 "changed since v1.0.0"

r="$(newRepo new-plugin)"
g -C "$r" tag v1.0.0
manifest "$r" 0.1.0; pluginFile "$r" a; commitAll "$r" "plugin added"
expect "plugin added after the tag" "$r" 0 "the plugin is new, version 0.1.0"

r="$(newRepo no-manifest)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
pluginFile "$r" b; rm "$r/plugin/.claude-plugin/plugin.json"
expect "manifest removed" "$r" 1 "is missing"

r="$(newRepo no-version)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
pluginFile "$r" b; printf '{"name": "hats"}\n' > "$r/plugin/.claude-plugin/plugin.json"
expect "manifest without a version" "$r" 1 'readable "version"'

r="$(newRepo bad-json)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
pluginFile "$r" b; printf '{"version": \n' > "$r/plugin/.claude-plugin/plugin.json"
expect "manifest that is not JSON" "$r" 1 'readable "version"'

r="$(newRepo released-no-version)"
mkdir -p "$r/plugin/.claude-plugin"; printf '{"name": "hats"}\n' > "$r/plugin/.claude-plugin/plugin.json"
pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
manifest "$r" 1.0.0; commitAll "$r" "version added"
expect "released manifest without a version" "$r" 1 "released number is unknown"

r="$(newRepo untracked)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
mkdir -p "$r/plugin/skills"; printf 'new\n' > "$r/plugin/skills/new.md"
expect "untracked new file under plugin/, same version" "$r" 1 "not above the released 1.0.0"

r="$(newRepo lowered)"
manifest "$r" 1.0.1; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
pluginFile "$r" b; manifest "$r" 1.0.0; commitAll "$r" "plugin change, lowered version"
expect "lowered version" "$r" 1 "is 1.0.0, not above the released 1.0.1"

r="$(newRepo version-sort)"
manifest "$r" 1.0.9; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
pluginFile "$r" b; manifest "$r" 1.0.10; commitAll "$r" "plugin change, 1.0.10"
expect "1.0.10 is above 1.0.9" "$r" 0 "1.0.9 -> 1.0.10"

r="$(newRepo prerelease-tag)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
pluginFile "$r" b; commitAll "$r" "plugin change"
g -C "$r" tag v1.1.0-rc1
g -C "$r" tag vtest
moveOn "$r"
expect "pre-release and non-version v* tags are not releases" "$r" 1 "changed since v1.0.0"

r="$(newRepo tag-on-head)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
pluginFile "$r" b; commitAll "$r" "plugin change"
g -C "$r" tag v1.1.0
expect "release tag on HEAD is not its own baseline" "$r" 1 "changed since v1.0.0"

r="$(newRepo marketplace)"
manifest "$r" 1.0.0; pluginFile "$r" a
mkdir -p "$r/.claude-plugin"; printf '{"plugins": []}\n' > "$r/.claude-plugin/marketplace.json"
commitAll "$r" plugin
g -C "$r" tag v1.0.0
printf '{"plugins": [1]}\n' > "$r/.claude-plugin/marketplace.json"; commitAll "$r" "marketplace change"
expect "marketplace.json change, same version" "$r" 1 "not above the released 1.0.0"

r="$(newRepo broken-tag-tree)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
broken="$(g -C "$r" rev-parse v1.0.0:plugin)"
rm -f "$r/.git/objects/${broken:0:2}/${broken:2}"
pluginFile "$r" b
expect "git ls-tree failing on a broken plugin tree at the tag" "$r" 1 "git ls-tree on v1.0.0 failed"

r="$(newRepo broken-tag-root)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
broken="$(g -C "$r" rev-parse 'v1.0.0^{tree}')"
rm -f "$r/.git/objects/${broken:0:2}/${broken:2}"
expect "git diff failing on a broken root tree at the tag" "$r" 1 "git diff against v1.0.0 failed"

fakeBin="$work/fake-bin"
mkdir -p "$fakeBin"
cat > "$fakeBin/git" <<'FAKE'
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == "$FAIL_GIT_ARG" ]]; then
        echo "fatal: made-up failure of git $*" >&2
        exit 128
    fi
done
exec "$REAL_GIT" "$@"
FAKE
chmod +x "$fakeBin/git"
realGit="$(command -v git)"
r="$(newRepo failing-tag)"
manifest "$r" 1.0.0; pluginFile "$r" a; commitAll "$r" plugin
g -C "$r" tag v1.0.0
moveOn "$r"
for failing in --points-at --list; do
    PATH="$fakeBin:$PATH" REAL_GIT="$realGit" FAIL_GIT_ARG="$failing" \
        expect "git tag $failing failing" "$r" 1 "git tag $failing"
done

source="$(newRepo shallow-source)"
manifest "$source" 1.0.0; pluginFile "$source" a; commitAll "$source" plugin
g -C "$source" tag v1.0.0
pluginFile "$source" b; commitAll "$source" "plugin change"
g clone -q --depth 1 --no-tags "file://$source" "$work/shallow" 2>/dev/null
mkdir -p "$work/shallow/Dev"; cp "$script" "$work/shallow/Dev/plugin-version-check.sh"
expect "shallow checkout without tags" "$work/shallow" 1 "shallow"

if (( failures > 0 )); then
    echo "plugin-version-check.test: $failures of $cases cases failed"
    exit 1
fi
echo "plugin-version-check.test: $cases cases passed"
