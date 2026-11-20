#!/usr/bin/env bash
# Checks the claude plugin commands Hats runs against a real Claude Code — inside a Docker
# container, never on this Mac: install --marketplace <folder> → list --json → uninstall
# --keep-data → list --json, the same commands with the same flags as SessionHandoffSteps; then
# install --marketplace zyuzka/hats → marketplace update hats → update hats@hats → list --json,
# the update Hats offers, with a project installation, a switched-off one and a lost repository.
#
# What it sets up: a Node container (image pinned by digest) labelled
# dev.tmk.hats.check=plugin-cli, Claude Code installed in it from npm at a pinned version, git
# installed by root, and this repository mounted read-only at /market as the marketplace folder.
# For the GitHub part a copy of its marketplace is committed inside the container into a bare
# repository that stands in for github.com/zyuzka/hats through git's insteadOf. Nothing else is
# mounted: the container's Claude Code keeps its settings in its own /home/node folders, and
# the script checks the mounts before it ends — ~/.claude of this Mac never goes in.
#
# What it prints: every command with its stdout, stderr and exit code, in the form the Swift
# tests keep in Tests/HatsTests/PluginCLISamples.swift — rerun it after a Claude Code update
# and compare. Exit code 0 when every step answered as expected, 1 otherwise, 2 when it could
# not run (no Docker, no network).
#
# The commands run from /, as Hats runs them.
#
# Cleanup: the container is removed on any exit, the image too if this script pulled it, and
# when ~/.claude/scripts/after-run-cleanup exists (or HATS_AFTER_RUN_CLEANUP names another
# one) it is called before and after with the container's label. Not part of swift test or CI:
# it needs Docker and the network.
set -uo pipefail

image="node:22.23.5-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee"
version="2.1.322"
label="dev.tmk.hats.check=plugin-cli"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="hats-plugin-cli-check-$$"
work=""
cleanup_tool="${HATS_AFTER_RUN_CLEANUP:-$HOME/.claude/scripts/after-run-cleanup}"
failures=0
pulled=""

finish() {
    docker rm -f "$name" >/dev/null 2>&1
    if [[ -n "$pulled" ]]; then
        docker image rm "$image" >/dev/null 2>&1 && echo "removed the image $image"
    fi
    if [[ -x "$cleanup_tool" && -n "$work" ]]; then
        "$cleanup_tool" after "$work/cleanup-state.json"
    fi
    if docker ps -aq --filter "label=$label" | grep -q .; then
        echo "FAIL a container labelled $label is still there" >&2
    else
        echo "no container labelled $label is left"
    fi
    if [[ -n "$work" ]]; then
        rm -rf "$work"
    fi
}

fail() {
    echo "FAIL $*" >&2
    failures=$((failures + 1))
}

docker info >/dev/null 2>&1 || { echo "Docker is not running" >&2; exit 2; }
trap finish EXIT
trap 'exit 130' INT TERM
work="$(mktemp -d)"
if [[ -x "$cleanup_tool" ]]; then
    "$cleanup_tool" before "$work/cleanup-state.json" --label "$label"
fi

if ! docker image inspect "$image" >/dev/null 2>&1; then
    pulled=1
    docker pull --quiet "$image" >/dev/null || { echo "could not pull $image" >&2; exit 2; }
fi

docker run --detach --rm --name "$name" --label "$label" --user node \
    --volume "$root:/market:ro" "$image" sleep infinity >/dev/null || { echo "the container did not start" >&2; exit 2; }

docker exec "$name" sh -c "npm install --global --prefix \$HOME/.npm-global --no-fund --no-audit \
    @anthropic-ai/claude-code@$version >/tmp/npm.log 2>&1" \
    || { docker exec "$name" tail -20 /tmp/npm.log >&2; echo "npm could not install Claude Code $version" >&2; exit 2; }

step() {
    local file="$1"
    shift
    docker exec "$name" sh -c 'PATH=$HOME/.npm-global/bin:$PATH; cd / && "$@"' claude "$@" \
        >"$work/$file.out" 2>"$work/$file.err"
    echo $? >"$work/$file.code"
    echo "=== $*"
    echo "--- stdout"
    cat "$work/$file.out"
    echo "--- stderr"
    cat "$work/$file.err"
    echo "--- exit $(cat "$work/$file.code")"
}

expect() {
    local file="$1" script="$2" what="$3"
    docker exec -i "$name" node -e "
        const text = require('fs').readFileSync(0, 'utf8');
        const code = Number(process.argv[1]);
        process.exit((${script}) ? 0 : 1);
    " "$(cat "$work/$file.code")" <"$work/$file.out" || fail "$what"
}

lastLine='JSON.parse(text.trim().split("\n").pop())'

step version claude --version
expect version "text.startsWith('$version ')" "claude --version says $version"

step help claude plugin install --help
expect help "text.includes('--marketplace')" "claude plugin install --help knows --marketplace"

step install claude plugin install hats --marketplace /market --scope user --json
expect install "code === 0 && $lastLine.outcome === 'ok'" "install answered ok with exit code 0"

step listed claude plugin list --json
expect listed "code === 0 && JSON.parse(text).some(p => p.id === 'hats@hats' && p.scope === 'user' \
    && p.readFromFolder === '/market/plugin')" "list --json shows hats@hats for the user, read from /market/plugin"

step marketplaces claude plugin marketplace list --json
expect marketplaces "code === 0 && JSON.parse(text).some(m => m.name === 'hats' && m.source === 'directory' \
    && m.path === '/market')" "marketplace list --json shows hats as the folder /market"

step uninstall claude plugin uninstall hats@hats --scope user --keep-data --json
expect uninstall "code === 0 && $lastLine.outcome === 'ok' && $lastLine.keptData === true" \
    "uninstall answered ok, data kept"

step unlisted claude plugin list --json
expect unlisted "code === 0 && !JSON.parse(text).some(p => p.id === 'hats@hats')" "list --json no longer shows hats@hats"

step kept claude plugin marketplace list --json
expect kept "code === 0 && JSON.parse(text).some(m => m.name === 'hats')" "the hats marketplace stays after the uninstall"

# The update, through a GitHub marketplace. git comes from root; a copy of the marketplace part of
# this repository is committed inside the container as version 0.1.0 into a bare repository, and
# the node user's global git configuration sends https://github.com/zyuzka/hats.git there — so the
# exact command Hats runs, install hats --marketplace zyuzka/hats, goes through. Four settings
# folders get 0.1.0 before the bump: A (plugin update alone), B (with a project installation in
# /tmp/proj beside it), C (switched off), D (the repository goes away before its update).
docker exec --user root "$name" sh -c 'apt-get update >/tmp/apt.log 2>&1 && apt-get install -y git >>/tmp/apt.log 2>&1' \
    || { docker exec "$name" tail -20 /tmp/apt.log >&2; echo "apt-get could not install git" >&2; exit 2; }

docker exec -i "$name" sh -s <<'PREPARE' || { echo "the bare repository could not be prepared" >&2; exit 2; }
set -e
mkdir -p /tmp/src
cp -R /market/.claude-plugin /market/plugin /tmp/src/
cd /tmp/src
node -e '
    const fs = require("fs");
    const file = "plugin/.claude-plugin/plugin.json";
    const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
    manifest.version = "0.1.0";
    fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + "\n");
'
git init -q --initial-branch=main
git -c user.name=check -c user.email=check@example.invalid add -A
git -c user.name=check -c user.email=check@example.invalid commit -qm 0.1.0
git init -q --bare --initial-branch=main /tmp/hats.git
git push -q /tmp/hats.git main
git config --global url./tmp/hats.git.insteadOf https://github.com/zyuzka/hats.git
mkdir -p /tmp/proj
cd /tmp/proj
git init -q
PREPARE

stepIn() {
    local file="$1" folder="$2" place="$3"
    shift 3
    docker exec --env CLAUDE_CONFIG_DIR="/home/node/$folder" "$name" sh -c \
        'mkdir -p "$CLAUDE_CONFIG_DIR"; PATH=$HOME/.npm-global/bin:$PATH; cd "$0" && "$@" </dev/null' "$place" "$@" \
        >"$work/$file.out" 2>"$work/$file.err"
    echo $? >"$work/$file.code"
    echo "=== [CLAUDE_CONFIG_DIR=/home/node/$folder, from $place] $*"
    echo "--- stdout"
    cat "$work/$file.out"
    echo "--- stderr"
    cat "$work/$file.err"
    echo "--- exit $(cat "$work/$file.code")"
}

for folder in a b c d; do
    stepIn "github-install-$folder" "cfg-$folder" / claude plugin install hats --marketplace zyuzka/hats --scope user --json
    expect "github-install-$folder" "code === 0 && $lastLine.outcome === 'ok'" "install from zyuzka/hats in cfg-$folder answered ok"
done

stepIn github-marketplaces cfg-a / claude plugin marketplace list --json
expect github-marketplaces "code === 0 && JSON.parse(text).some(m => m.name === 'hats' && m.source === 'github' \
    && m.repo === 'zyuzka/hats')" "marketplace list --json shows hats from github, zyuzka/hats"
origin="$(docker exec "$name" git -C /home/node/cfg-a/plugins/marketplaces/hats remote get-url origin 2>&1)"
echo "=== the clone of the hats marketplace in cfg-a comes from: $origin"
if [[ "$origin" != "/tmp/hats.git" ]]; then
    fail "the GitHub address was not sent to the bare repository: these steps did not measure Hats' command, stop here"
    exit 1
fi

stepIn github-list-a cfg-a / claude plugin list --json
expect github-list-a "code === 0 && JSON.parse(text).some(p => p.id === 'hats@hats' && p.scope === 'user' \
    && p.version === '0.1.0' && p.readFromFolder === undefined)" "list --json shows hats@hats 0.1.0 for the user, not from a folder"

stepIn project-install cfg-b /tmp/proj claude plugin install hats@hats --scope project --json
expect project-install "code === 0 && $lastLine.outcome === 'ok'" "the project installation in /tmp/proj answered ok"
stepIn both-list-b cfg-b / claude plugin list --json
expect both-list-b "code === 0 && JSON.parse(text).some(p => p.scope === 'user' && p.version === '0.1.0') \
    && JSON.parse(text).some(p => p.scope === 'project' && p.version === '0.1.0')" \
    "list --json from / shows the user and the project installation in cfg-b, both 0.1.0"

stepIn disable-c cfg-c / claude plugin disable hats@hats --scope user --json
expect disable-c "code === 0 && $lastLine.outcome === 'ok'" "disable in cfg-c answered ok"
stepIn disabled-list-c cfg-c / claude plugin list --json
expect disabled-list-c "code === 0 && JSON.parse(text).some(p => p.id === 'hats@hats' && p.enabled === false \
    && p.version === '0.1.0')" "list --json shows hats@hats 0.1.0 switched off in cfg-c"

docker exec -i "$name" sh -s <<'BUMP' || { echo "version 0.2.0 could not be committed" >&2; exit 2; }
set -e
cd /tmp/src
node -e '
    const fs = require("fs");
    const file = "plugin/.claude-plugin/plugin.json";
    const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
    manifest.version = "0.2.0";
    fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + "\n");
'
git -c user.name=check -c user.email=check@example.invalid commit -qam 0.2.0
git push -q /tmp/hats.git main
BUMP

stepIn update-help cfg-a / claude plugin update --help
expect update-help "code === 0 && text.includes('--json')" "claude plugin update --help knows --json"
stepIn marketplace-update-help cfg-a / claude plugin marketplace update --help
expect marketplace-update-help "code === 0 && text.includes('--json')" "claude plugin marketplace update --help knows --json"

stepIn update-alone-a cfg-a / claude plugin update hats@hats --scope user --json
expect update-alone-a "code === 0 && $lastLine.outcome === 'ok'" "plugin update alone in cfg-a answered ok"
echo "=== MEASURE plugin update alone, without marketplace update, moved cfg-a to: $(docker exec -i "$name" \
    node -e 'console.log(JSON.parse(require("fs").readFileSync(0, "utf8").trim().split("\n").pop()).newVersion)' \
    <"$work/update-alone-a.out")"

docker exec "$name" cp /home/node/cfg-b/settings.json /tmp/settings-b-before.json \
    || fail "cfg-b has a settings.json to compare after the update"
stepIn marketplace-update-b cfg-b / claude plugin marketplace update hats --json
expect marketplace-update-b "code === 0 && $lastLine.outcome === 'ok'" "marketplace update in cfg-b answered ok"
stepIn update-b cfg-b / claude plugin update hats@hats --scope user --json
expect update-b "code === 0 && $lastLine.updateOutcome === 'updated' && $lastLine.newVersion === '0.2.0'" \
    "plugin update in cfg-b updated hats@hats to 0.2.0"
docker exec "$name" cat /home/node/cfg-b/settings.json >"$work/settings-b-after.out"
echo $? >"$work/settings-b-after.code"
echo "=== cfg-b settings.json after the update"
cat "$work/settings-b-after.out"
expect settings-b-after "code === 0 && require('util').isDeepStrictEqual(JSON.parse(text), \
    JSON.parse(require('fs').readFileSync('/tmp/settings-b-before.json', 'utf8')))" \
    "settings.json of cfg-b parses the same after marketplace update and plugin update as before them"
stepIn updated-list-b cfg-b / claude plugin list --json
expect updated-list-b "code === 0 && JSON.parse(text).some(p => p.scope === 'user' && p.version === '0.2.0') \
    && JSON.parse(text).some(p => p.scope === 'project' && p.version === '0.1.0')" \
    "list --json from / shows the user installation at 0.2.0 and the project one still at 0.1.0"
stepIn updated-project-list-b cfg-b /tmp/proj claude plugin list --json
expect updated-project-list-b "code === 0 && JSON.parse(text).some(p => p.scope === 'project' && p.version === '0.1.0' \
    && p.projectPath === '/tmp/proj')" "list --json from /tmp/proj shows the project installation still at 0.1.0"
cache="$(docker exec "$name" ls /home/node/cfg-b/plugins/cache/hats/hats 2>&1 | tr '\n' ' ')"
echo "=== the plugin cache of cfg-b holds: $cache"
[[ "$cache" == "0.1.0 0.2.0 " ]] || fail "the cache of cfg-b keeps 0.1.0 for the project beside 0.2.0"
stepIn update-again-b cfg-b / claude plugin update hats@hats --scope user --json
expect update-again-b "code === 0 && $lastLine.updateOutcome === 'up_to_date' && $lastLine.newVersion === '0.2.0'" \
    "a second plugin update in cfg-b answers that 0.2.0 is the latest"

stepIn marketplace-update-c cfg-c / claude plugin marketplace update hats --json
expect marketplace-update-c "code === 0 && $lastLine.outcome === 'ok'" "marketplace update in cfg-c answered ok"
stepIn update-c cfg-c / claude plugin update hats@hats --scope user --json
expect update-c "code === 0 && $lastLine.newVersion === '0.2.0'" "plugin update in cfg-c updated the switched-off plugin to 0.2.0"
stepIn updated-list-c cfg-c / claude plugin list --json
expect updated-list-c "code === 0 && JSON.parse(text).some(p => p.id === 'hats@hats' && p.version === '0.2.0' \
    && p.enabled === false)" "after the update hats@hats in cfg-c is 0.2.0 and still switched off"
echo "=== MEASURE the plugin cache of cfg-c after the update holds: $(docker exec "$name" \
    ls /home/node/cfg-c/plugins/cache/hats/hats 2>&1 | tr '\n' ' ')"

docker exec "$name" mv /tmp/hats.git /tmp/hats.git.gone || { echo "the bare repository could not be moved away" >&2; exit 2; }
stepIn marketplace-update-gone-d cfg-d / claude plugin marketplace update hats --json
expect marketplace-update-gone-d "code !== 0 && $lastLine.outcome === 'failed'" \
    "marketplace update in cfg-d without the repository failed with a non-zero exit code"
stepIn update-gone-d cfg-d / claude plugin update hats@hats --scope user --json
expect update-gone-d "code === 0 && $lastLine.newVersion === '0.1.0'" \
    "plugin update in cfg-d without the repository leaves 0.1.0"
echo "=== MEASURE plugin update in cfg-d without the repository reported refreshFailed: $(docker exec -i "$name" \
    node -e 'console.log(JSON.parse(require("fs").readFileSync(0, "utf8").trim().split("\n").pop()).refreshFailed)' \
    <"$work/update-gone-d.out")"
stepIn gone-list-d cfg-d / claude plugin list --json
expect gone-list-d "code === 0 && JSON.parse(text).some(p => p.id === 'hats@hats' && p.version === '0.1.0')" \
    "after the failed update hats@hats in cfg-d is still 0.1.0"

stepIn github-uninstall-b cfg-b / claude plugin uninstall hats@hats --scope user --keep-data --json
expect github-uninstall-b "code === 0 && $lastLine.outcome === 'ok'" "uninstall of the user installation in cfg-b answered ok"
stepIn kept-project-list-b cfg-b /tmp/proj claude plugin list --json
expect kept-project-list-b "code === 0 && JSON.parse(text).length === 1 && JSON.parse(text)[0].scope === 'project' \
    && JSON.parse(text)[0].version === '0.1.0'" "after the uninstall only the project installation is left, intact"

mounts="$(docker inspect --format '{{range .Mounts}}{{.Type}} {{.Source}} {{.Destination}} {{.RW}};{{end}}' "$name")"
echo "=== mounts: $mounts"
[[ "$mounts" == "bind $root /market false;" ]] || fail "the only mount is $root at /market, read-only"
[[ "$mounts" != *"/.claude"* ]] || fail "nothing under ~/.claude is mounted"

if ((failures > 0)); then
    echo "$failures check(s) failed" >&2
    exit 1
fi
echo "every check passed with Claude Code $version"
