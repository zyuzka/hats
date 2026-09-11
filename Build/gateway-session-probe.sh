#!/usr/bin/env bash
# Which running Claude Code sessions would stop working if the gateway went down,
# and whether the caller has said the build may stop them anyway.
#
# Sourced by build-app.sh. Defines functions
# and nothing else, so sourcing it has no effect of its own. It is a separate file
# because build-app.sh cannot be sourced without building, so nothing living inside
# build-app.sh can be checked without side effects.
#
# THIS FILE DOES NOT DECIDE WHICH SESSIONS ARE AT RISK. It asks the app, over the
# gateway's own local control path, and the app answers with the predicate it already
# uses for the same question — `GatewayRetirement.dependants(onAnyOf:among:)` in
# `SessionsAtRisk.body`, over the session reader the gateway server holds
# (`SessionDiscovery.everySessionSeenRecently`, which falls back to a fresh
# `everySessionThatHoldsAPort` sweep when its one-second memory is empty). That is
# deliberate and it is the third design here.
#
# The first version matched the literal text `http://127.0.0.1:` in each session's
# environment. The second reimplemented the app's reading of an address in shell. The
# review gate then produced nine confirmed findings across three passes and every one
# of them was the same class — the shell reimplementation disagreeing with what the
# app or the OS actually does:
#
#   * the literal match missed `http://localhost:8787`;
#   * userinfo was stripped before the path, so an `@` in a query ate the host;
#   * the glob `127.*` accepted 127.0.0.2 and 127.evil-proxy.local, which the app
#     does not, because the Swift compares inet_aton's result for EQUALITY with
#     INADDR_LOOPBACK rather than membership of 127/8;
#   * `127.0.0.01` and `0177.0.0.1` were rejected, which the app accepts, because
#     inet_aton canonicalises octal and zero-padded octets;
#   * `pgrep -x claude` excludes its own ancestors, so the session that RUNS the
#     build could never appear in the list — precisely the session the guard exists
#     for, and precisely the 2026-09-02 incident;
#   * `ps eww` prints a header for a live process whose environment it will not show,
#     so the string was never empty and the "unreadable counts as at risk" promise
#     could not fire.
#
# A fourth shell fix would have been the fourth iteration of one class. The app reads
# the whole process table (`ps -eo pid=,comm=`), has no ancestor rule, fills each
# session's route from that process's own environment, and its predicate is covered by
# the Swift test suite. Asking it is not a shortcut; it is the only way the two answers
# cannot drift.
#
# What stays here is what is genuinely the shell's own business: reading the settings,
# talking to the endpoint, deciding what silence means, and printing.

# The settings file has lived in three places: ~/.claude/state/acc-switch, then
# ~/.claude/state/hats after the rename, and now Application Support where a macOS app's
# state belongs. The app moves it on its first run, and a build can happen before that
# run, so the older paths are read as fallbacks — newest first, and only when the one
# before it is absent.
hatsSettingsFile() {
    if [[ -n "${HATS_SETTINGS_FILE:-}" ]]; then
        printf '%s' "$HATS_SETTINGS_FILE"
        return
    fi
    local current="$HOME/Library/Application Support/Hats/settings.json"
    local candidate
    for candidate in "$current" \
                     "$HOME/.claude/state/hats/settings.json" \
                     "$HOME/.claude/state/acc-switch/settings.json"; do
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return
        fi
    done
    printf '%s' "$current"
}

# The settings file is written by JSONEncoder with sorted keys and one value per line,
# so a line-anchored read is enough and adding a JSON parser to a build script is not.
#
# `-E` rather than a basic expression on purpose: `\|` alternation is a GNU extension
# and this runs on BSD sed, where it matches nothing and the flag silently reads as
# empty. The checks caught it, which is the whole reason they exist.
settingNumber() {
    sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "$2" 2>/dev/null | head -1
}

settingFlag() {
    sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" "$2" 2>/dev/null | head -1
}

# The token the rest of the guard reads as "the answer could not be had". It is not a
# pid and cannot collide with one.
readonly atRiskUnknown="unknown"

# Pure: turns the endpoint's body into a pid list, or into the unknown token. An empty
# body, a missing header line, or `readable 0` — the app saying it could not read the
# process table — all mean unknown, and unknown refuses.
pidsFromAnswer() {
    local body="$1" first
    [[ -n "$body" ]] || { printf '%s\n' "$atRiskUnknown"; return 0; }
    first="$(head -1 <<< "$body")"
    if [[ "$first" != "readable 1" ]]; then
        printf '%s\n' "$atRiskUnknown"
        return 0
    fi
    sed -n 's/^pid \([0-9]\{1,\}\)$/\1/p' <<< "$body"
}

# Asks the gateway. Separated from the parsing so the parsing can be checked without a
# network, and kept overridable so the checks can stand a fake in its place.
gatewayAnswer() {
    local port="$1"
    curl -sS --max-time 4 "http://127.0.0.1:${port}/__gateway__/sessions-at-risk" 2>/dev/null || true
}

sessionsTheBuildWouldBreak() {
    local file port enabled
    file="$(hatsSettingsFile)"
    if [[ ! -r "$file" ]]; then
        printf '%s\n' "$atRiskUnknown"
        return 0
    fi
    # A gateway that is switched off carries no session, so there is nothing to break.
    enabled="$(settingFlag isGatewayEnabled "$file")"
    if [[ "$enabled" == false ]]; then
        return 0
    fi
    port="$(settingNumber gatewayPort "$file")"
    if [[ -z "$port" ]]; then
        printf '%s\n' "$atRiskUnknown"
        return 0
    fi
    pidsFromAnswer "$(gatewayAnswer "$port")"
}

# The override has to be said affirmatively. Testing only for emptiness made
# HATS_BUILD_MAY_STOP_SESSIONS=0 — the ordinary shell spelling of "no" — switch the
# whole guard off, which is the opposite of what the caller asked for and of what the
# refusal message advertises.
buildMayStopSessions() {
    case "${HATS_BUILD_MAY_STOP_SESSIONS:-}" in
        1|y|Y|yes|YES|true|TRUE) return 0 ;;
        *) return 1 ;;
    esac
}

# `printf '  %s\n' $list` with the expansion unquoted word-splits on spaces as well as
# newlines, so under bash a list of "1234" and "unknown" printed fine but anything
# carrying a space came apart from its own line. Quoting the whole variable is not the
# fix either — that indents only the first line. One line at a time is.
indentEachLine() {
    local line
    while IFS= read -r line; do printf '  %s\n' "$line"; done <<< "$1"
}

# What to print for each entry: a pid is a pid, and the unknown token needs saying in
# words or the refusal reads as a nonsense process id.
describeAtRisk() {
    local line out=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$line" == "$atRiskUnknown" ]]; then
            out+="the app did not answer, so this cannot be ruled out"$'\n'
        else
            out+="$line"$'\n'
        fi
    done <<< "$1"
    printf '%s' "${out%$'\n'}"
}
