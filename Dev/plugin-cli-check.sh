#!/usr/bin/env bash
# Checks the claude plugin commands Hats runs against a real Claude Code — inside a Docker
# container, never on this Mac: install --marketplace <folder> → list --json → uninstall
# --keep-data → list --json, the same commands with the same flags as SessionHandoffSteps.
#
# What it sets up: a Node container (image pinned by digest) labelled
# dev.tmk.hats.check=plugin-cli, Claude Code installed in it from npm at a pinned version, and
# this repository mounted read-only at /market as the marketplace folder. Nothing else is
# mounted: the container's Claude Code keeps its settings in its own /home/node/.claude, and
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

mounts="$(docker inspect --format '{{range .Mounts}}{{.Type}} {{.Source}} {{.Destination}} {{.RW}};{{end}}' "$name")"
echo "=== mounts: $mounts"
[[ "$mounts" == "bind $root /market false;" ]] || fail "the only mount is $root at /market, read-only"
[[ "$mounts" != *"/.claude"* ]] || fail "nothing under ~/.claude is mounted"

if ((failures > 0)); then
    echo "$failures check(s) failed" >&2
    exit 1
fi
echo "every check passed with Claude Code $version"
