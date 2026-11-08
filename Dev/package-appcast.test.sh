#!/usr/bin/env bash
# Checks package-appcast.sh: which changelog entry is taken, the refusals, and the feed it
# writes. Nothing is signed: the signature and the length are made-up values, because what
# is checked here is where each value lands, not whether Sparkle accepts the signature.
#
# Run it directly: ./package-appcast.test.sh — prints one line per failure and exits
# non-zero if there are any.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
. ./package-appcast.sh

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

holds() {
    local what="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL ${what}: [${needle}] is not in the output" >&2
        failures=$((failures + 1))
    fi
}

refuses() {
    local what="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "FAIL ${what}: want a refusal, got success" >&2
        failures=$((failures + 1))
    fi
}

cat > "$work/CHANGELOG.md" <<'MD'
# Hats — what changed

## 0.4.10 — 2026-12-01

- ten

## 0.4.1 — 2026-11-20

- one, with `code` and **bold**

## 0.4.0 — 2026-11-08

## 0.3.9 — 2026-11-01

- nine
MD

equals "the heading is matched as a whole version, not a prefix" \
    "- one, with \`code\` and **bold**" \
    "$(getChangelogEntry 0.4.1 "$work/CHANGELOG.md" | sed '/^$/d')"
equals "an entry ends at the next heading" \
    "- ten" \
    "$(getChangelogEntry 0.4.10 "$work/CHANGELOG.md" | sed '/^$/d')"

equals "a two-part minimum system gets a patch" "13.0.0" "$(getThreePartVersion 13.0)"
equals "a one-part minimum system gets two"     "13.0.0" "$(getThreePartVersion 13)"
equals "a three-part one stays as it is"        "13.4.1" "$(getThreePartVersion 13.4.1)"

refuses "a heading with nothing under it" \
    checkReleaseEntry 0.4.0 "$(getChangelogEntry 0.4.0 "$work/CHANGELOG.md")"
refuses "an entry that would close the CDATA section" \
    checkReleaseEntry 0.4.1 "- see a[1]]> b"
refuses "the feed for an empty entry" \
    createAppcast 0.4.0 0.4.0 13.0.0 Hats-0.4.0.dmg c2ln 1234 "" "Sun, 08 Nov 2026 17:00:00 +0000"

entry="$(getChangelogEntry 0.4.1 "$work/CHANGELOG.md")"
if ! feed="$(createAppcast 0.4.1 41 "$(getThreePartVersion 13.0)" Hats-0.4.1.dmg c2ln 1234 "$entry" \
        "Sun, 08 Nov 2026 17:00:00 +0000")"; then
    echo "FAIL the feed for a good entry: want success, got a refusal" >&2
    failures=$((failures + 1))
fi
holds "Sparkle compares the bundle version"   "<sparkle:version>41</sparkle:version>" "$feed"
holds "a person reads the shown version"      "<sparkle:shortVersionString>0.4.1</sparkle:shortVersionString>" "$feed"
holds "the minimum system has three parts"    "<sparkle:minimumSystemVersion>13.0.0</sparkle:minimumSystemVersion>" "$feed"
holds "the image comes from the release tag"  'url="https://github.com/zyuzka/hats/releases/download/v0.4.1/Hats-0.4.1.dmg"' "$feed"
holds "the signature lands on the enclosure"  'sparkle:edSignature="c2ln"' "$feed"
holds "the length lands on the enclosure"     'length="1234"' "$feed"
holds "what's new is this version's entry"    "- one, with \`code\` and **bold**" "$feed"
holds "the entry is markdown"                 '<description sparkle:format="markdown"><![CDATA[' "$feed"
equals "no other version's entry rides along" "0" "$(grep -c -- '- ten\|- nine' <<< "$feed")"
if ! xmllint --noout - <<< "$feed" 2>"$work/xmllint.err"; then
    echo "FAIL the feed is not well-formed XML: $(cat "$work/xmllint.err")" >&2
    failures=$((failures + 1))
fi

if (( failures > 0 )); then
    echo "package-appcast: $failures failure(s)" >&2
    exit 1
fi
echo "package-appcast: all checks passed"
