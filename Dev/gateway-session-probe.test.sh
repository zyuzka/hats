#!/usr/bin/env bash
# Checks gateway-session-probe.sh: the settings reading, the parsing of the app's
# answer, what silence is taken to mean, the override, and the printing.
#
# It does NOT check which sessions are at risk — that predicate lives in the app now,
# in GatewayRetirement over SessionDiscovery, and is covered by the Swift suite. This
# file exists to check the shell's own share of the job.
#
# Run it directly: ./gateway-session-probe.test.sh — prints one line per failure and
# exits non-zero if there are any. It touches no processes and makes no request: the
# endpoint is replaced by a function and the settings by a temporary file.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
. ../Build/gateway-session-probe.sh

failures=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

equals() {
    local what="$1" want="$2" got="$3"
    if [[ "$want" != "$got" ]]; then
        echo "FAIL ${what}: want [${want}] got [${got}]" >&2
        failures=$((failures + 1))
    fi
}

settingsSaying() {
    printf '%s\n' "$1" > "$work/settings.json"
    printf '%s' "$work/settings.json"
}

mayStop() {
    if ! HATS_BUILD_MAY_STOP_SESSIONS="$1" buildMayStopSessions; then
        echo "FAIL buildMayStopSessions [$1]: want permission, got refusal" >&2
        failures=$((failures + 1))
    fi
}

mayNotStop() {
    if HATS_BUILD_MAY_STOP_SESSIONS="$1" buildMayStopSessions; then
        echo "FAIL buildMayStopSessions [$1]: want the guard to stay on, got permission" >&2
        failures=$((failures + 1))
    fi
}

full='{
  "gatewayPort" : 8787,
  "gatewaySettleSeconds" : 2,
  "isGatewayEnabled" : true
}'

file="$(settingsSaying "$full")"
equals "the port is read out of the settings"    "8787" "$(settingNumber gatewayPort "$file")"
equals "the settle is read the same way"         "2"    "$(settingNumber gatewaySettleSeconds "$file")"
equals "a flag is read as a word"                "true" "$(settingFlag isGatewayEnabled "$file")"
equals "a key that is not there reads as empty"  ""     "$(settingNumber nosuchKey "$file")"

equals "an answer with two pids" "47193
80442" "$(pidsFromAnswer 'readable 1
pid 47193
pid 80442')"
equals "an answer with no pids is not unknown" "" "$(pidsFromAnswer 'readable 1')"
equals "the app saying it could not read is unknown" "unknown" "$(pidsFromAnswer 'readable 0')"
equals "an empty body is unknown"                   "unknown" "$(pidsFromAnswer '')"
equals "a body that does not start with the header is unknown" "unknown" \
    "$(pidsFromAnswer '<html>404</html>')"
equals "a pid line that is not a number is ignored" "47193" "$(pidsFromAnswer 'readable 1
pid 47193
pid not-a-number')"

gatewayAnswer() { printf 'readable 1\npid 4242\n'; }
HATS_SETTINGS_FILE="$file"
equals "the pids come from the app" "4242" "$(sessionsTheBuildWouldBreak)"

gatewayAnswer() { printf ''; }
equals "silence from the app refuses rather than allows" "unknown" "$(sessionsTheBuildWouldBreak)"

gatewayAnswer() { printf 'readable 1\npid 4242\n'; }
HATS_SETTINGS_FILE="$(settingsSaying '{
  "gatewayPort" : 8787,
  "isGatewayEnabled" : false
}')"
equals "a gateway switched off carries nothing to break" "" "$(sessionsTheBuildWouldBreak)"

HATS_SETTINGS_FILE="$(settingsSaying '{
  "isGatewayEnabled" : true
}')"
equals "settings without a port are unknown" "unknown" "$(sessionsTheBuildWouldBreak)"

HATS_SETTINGS_FILE="$work/there-is-no-such-file.json"
equals "unreadable settings are unknown" "unknown" "$(sessionsTheBuildWouldBreak)"

mayStop 1
mayStop yes
mayStop true
mayNotStop ""
mayNotStop 0
mayNotStop no
mayNotStop false

equals "a pid prints as itself" "47193" "$(describeAtRisk '47193')"
equals "the unknown token prints as words" \
    "the app did not answer, so this cannot be ruled out" "$(describeAtRisk 'unknown')"
equals "a mixed list keeps both" "47193
the app did not answer, so this cannot be ruled out" "$(describeAtRisk '47193
unknown')"

equals "each entry keeps its own line, spaces and all" \
    '  47193
  the app did not answer, so this cannot be ruled out' "$(indentEachLine "$(describeAtRisk '47193
unknown')")"

if [[ "$failures" -ne 0 ]]; then
    echo "gateway-session-probe: ${failures} failure(s)" >&2
    exit 1
fi
echo "gateway-session-probe: all checks passed"
