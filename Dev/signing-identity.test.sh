#!/usr/bin/env bash
# Checks signing-identity.sh: which identity the build signs with, given what
# `security find-identity -v -p codesigning` lists and what HATS_SIGNING_IDENTITY says.
#
# Run it directly: ./signing-identity.test.sh — prints one line per failure and exits
# non-zero if there are any. It reads no keychain: every list below is made up.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
. ../Build/gateway-session-probe.sh
. ../Build/signing-identity.sh

failures=0

developerId="AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111"
renewedDeveloperId="CCCC3333CCCC3333CCCC3333CCCC3333CCCC3333"
hatsDev="BBBB2222BBBB2222BBBB2222BBBB2222BBBB2222"
lookalike="DDDD4444DDDD4444DDDD4444DDDD4444DDDD4444"
developerIdName="Developer ID Application: Example Person (TEAM123456)"

everything="  1) $lookalike \"Hats Developer\"
  2) $developerId \"$developerIdName\"
  3) $hatsDev \"Hats Dev\"
  4) $renewedDeveloperId \"$developerIdName\"
     4 valid identities found"

selfSignedOnly="  1) $lookalike \"Hats Developer\"
  2) $hatsDev \"Hats Dev\"
     2 valid identities found"

lookalikeOnly="  1) $lookalike \"Hats Developer\"
     1 valid identities found"

nothing="     0 valid identities found"

chosen() {
    local list="$1" asked="$2"
    (
        AVAILABLE_IDENTITIES="$list"
        HATS_SIGNING_IDENTITY="$asked"
        chooseSigningIdentity 2>/dev/null
        printf '%s|%s' "$IDENTITY" "$IDENTITY_NAME"
    ) || printf 'refused'
}

equals() {
    local what="$1" want="$2" got="$3"
    if [[ "$want" != "$got" ]]; then
        echo "FAIL ${what}: want [${want}] got [${got}]" >&2
        failures=$((failures + 1))
    fi
}

equals "a Developer ID wins over the self-signed certificate" \
    "$developerId|$developerIdName" "$(chosen "$everything" "")"
equals "without a Developer ID the self-signed certificate is taken by its exact name" \
    "$hatsDev|Hats Dev" "$(chosen "$selfSignedOnly" "")"
equals "a certificate whose name only starts with Hats Dev is not the self-signed one" \
    "-|ad-hoc" "$(chosen "$lookalikeOnly" "")"
equals "an empty keychain signs ad-hoc" "-|ad-hoc" "$(chosen "$nothing" "")"

equals "a dash asks for ad-hoc whatever the keychain holds" "-|ad-hoc" "$(chosen "$everything" "-")"
equals "a full name is taken by its hash" "$hatsDev|Hats Dev" "$(chosen "$everything" "Hats Dev")"
equals "a name two certificates share takes the first one listed" \
    "$developerId|$developerIdName" "$(chosen "$everything" "$developerIdName")"
equals "a hash in lower case is the same hash" \
    "$developerId|$developerIdName" "$(chosen "$everything" "aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111")"
equals "a lookalike asked for by its own full name is taken" \
    "$lookalike|Hats Developer" "$(chosen "$everything" "Hats Developer")"

equals "the list's line number names no identity" "refused" "$(chosen "$everything" "1")"
equals "a part of a name names no identity" "refused" "$(chosen "$everything" "Dev")"
equals "a part of a hash names no identity" "refused" "$(chosen "$everything" "AAAA")"
equals "a value naming nothing is refused, not passed on" "refused" "$(chosen "$nothing" "Hats Dev")"

if [[ "$failures" -ne 0 ]]; then
    echo "signing-identity: ${failures} failure(s)" >&2
    exit 1
fi
echo "signing-identity: all checks passed"
