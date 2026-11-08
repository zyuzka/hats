# Decides which identity Build/build-app.sh signs with, out of what
# `security find-identity -v -p codesigning` listed into AVAILABLE_IDENTITIES and what
# HATS_SIGNING_IDENTITY says. The order and the reasons are in build-app.sh, beside the
# signing itself. It lives in its own file so Dev/signing-identity.test.sh can run the
# same choice against a made-up list instead of a keychain.

identityNameMatching() {
    WANTED="$1" awk -F'"' 'NF >= 3 {
        split($1, field, " ")
        if (field[2] == toupper(ENVIRON["WANTED"])) { print $2; exit }
    }' <<< "$AVAILABLE_IDENTITIES"
}

identityHashMatching() {
    WANTED="$1" awk -F'"' 'NF >= 3 {
        split($1, field, " ")
        if (field[2] == toupper(ENVIRON["WANTED"]) || $2 == ENVIRON["WANTED"]) { print field[2]; exit }
    }' <<< "$AVAILABLE_IDENTITIES"
}

identityHashNamedFrom() {
    PREFIX="$1" awk -F'"' 'NF >= 3 && index($2, ENVIRON["PREFIX"]) == 1 {
        split($1, field, " "); print field[2]; exit
    }' <<< "$AVAILABLE_IDENTITIES"
}

chooseSigningIdentity() {
    if [[ -n "${HATS_SIGNING_IDENTITY:-}" ]]; then
        IDENTITY="$HATS_SIGNING_IDENTITY"
        if [[ "$IDENTITY" == "-" ]]; then
            IDENTITY_NAME="ad-hoc"
        else
            IDENTITY="$(identityHashMatching "$HATS_SIGNING_IDENTITY")"
            IDENTITY_NAME="$(identityNameMatching "$IDENTITY")"
            if [[ -z "$IDENTITY_NAME" ]]; then
                echo "HATS_SIGNING_IDENTITY=$HATS_SIGNING_IDENTITY names no valid signing identity." >&2
                echo "valid ones, from security find-identity -v -p codesigning:" >&2
                indentEachLine "$AVAILABLE_IDENTITIES" >&2
                exit 1
            fi
        fi
    elif IDENTITY="$(identityHashNamedFrom "Developer ID Application: ")" && [[ -n "$IDENTITY" ]]; then
        IDENTITY_NAME="$(identityNameMatching "$IDENTITY")"
    elif IDENTITY="$(identityHashMatching "Hats Dev")" && [[ -n "$IDENTITY" ]]; then
        IDENTITY_NAME="$(identityNameMatching "$IDENTITY")"
    else
        IDENTITY="-"
        IDENTITY_NAME="ad-hoc"
    fi
}
