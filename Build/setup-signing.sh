#!/usr/bin/env bash
# Creates the self-signed identity that keeps Hats's signature stable.
#
# **Why a stable signature matters, and it is not about trust.** macOS ties an
# Automation grant to the app's *designated requirement*. Under an ad-hoc signature
# that requirement is the code hash:
#
#   designated => cdhash H"f3a5844fa614d08d..."
#
# so every rebuild is a different application, and the permission the user granted
# is gone. With a certificate it becomes:
#
#   designated => identifier "dev.tmk.hats" and certificate leaf = H"051cfd05..."
#
# which is identical across rebuilds — verified by building twice. The grant then
# survives an update, which is the difference between "replace the app" and
# "replace the app and re-approve two dialogs".
#
# It does NOT satisfy Gatekeeper. A self-signed certificate is not a Developer ID,
# so a fresh download still needs the one-time right-click-Open. Two separate
# mechanisms, and only one of them is fixable without an Apple account.
set -euo pipefail

IDENTITY="Hats Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# An identity that already exists keeps whatever ACL it was imported with, and this
# script cannot read that ACL: `security dump-keychain -a` raises a keychain prompt,
# so there is nothing to check silently. An identity created by a version of this
# script that passed `-A` therefore stays "any application" forever, and returning
# here without saying so would let the removal of `-A` look like it had reached
# everyone. Re-importing over it is not the answer either — that is someone's
# keychain, and the reset has to be their decision.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "already present: $IDENTITY"
    security find-identity -v -p codesigning | grep "$IDENTITY" | sed 's/^/  /'
    echo
    echo "This script cannot tell which ACL that identity carries — reading it raises" >&2
    echo "a keychain prompt. If it was created before the ACL was narrowed, it still" >&2
    echo "says \"any application\", which means every process running as you can use" >&2
    echo "the key. To replace it with a narrowed one:" >&2
    echo >&2
    echo "  security delete-identity -c '$IDENTITY' '$KEYCHAIN'" >&2
    echo >&2
    echo "-c matches by common name and the man page requires the match to be unique," >&2
    echo "so with more than one identity of this name use the hash printed above and" >&2
    echo "add -t to drop its trust settings as well. find-identity prints the SHA-1," >&2
    echo "which is one of the two forms -Z accepts:" >&2
    echo >&2
    echo "  security delete-identity -Z <the 40-character hash above> -t '$KEYCHAIN'" >&2
    echo >&2
    echo "  ./Build/setup-signing.sh && ./Build/build-app.sh" >&2
    echo >&2
    echo "Rebuilding is part of it: the certificate changes, so the designated" >&2
    echo "requirement changes and the Automation grant has to be given once more." >&2
    echo >&2
    # Exit 0 here read as "setup is complete", and the caller went on to sign with a key
    # that may still be available to every process running as you. The one thing this
    # script knows is that it cannot know; saying so and failing is honest, and the
    # acknowledgement is explicit rather than a flag someone passes by habit.
    if [[ "${HATS_ACCEPT_UNVERIFIED_ACL:-}" == "yes" ]]; then
        echo "HATS_ACCEPT_UNVERIFIED_ACL=yes — proceeding with the existing" >&2
        echo "identity and its unknown ACL." >&2
        exit 0
    fi
    echo "Refusing to report setup as complete: the ACL of that identity cannot be" >&2
    echo "verified from here. Replace it as above, or re-run with" >&2
    echo "HATS_ACCEPT_UNVERIFIED_ACL=yes to accept it as it is." >&2
    exit 1
fi

WORK="$(mktemp -d)"
# The private key must not outlive this script anywhere but the keychain.
# EXIT does the cleanup; the signal traps only turn the signal into an exit, which runs
# it. A bare `trap '<cleanup>' INT TERM` REPLACES the default action, so Ctrl-C ran the
# cleanup and the script carried on to package a bundle nobody was waiting for.
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$WORK/ext.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# stderr is kept and printed on failure. Discarded, `set -e` killed the script with
# no output at all — including when openssl was missing entirely, or when the stock
# LibreSSL rejected `-legacy` below — and the operator had nothing to act on.
if ! OPENSSL_ERR="$(openssl req -x509 -newkey rsa:2048 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -nodes -config "$WORK/ext.cnf" 2>&1 >/dev/null)"; then
    echo "openssl req failed:" >&2
    echo "$OPENSSL_ERR" >&2
    exit 1
fi

# `-legacy` because macOS `security` cannot read a PKCS#12 written with OpenSSL 3's
# default cipher, and a non-empty password because it rejects an empty one with
# "MAC verification failed" — which reads as a wrong password rather than a
# limitation. Both found by trying 2026-08-20.
if ! OPENSSL_ERR="$(openssl pkcs12 -export -legacy \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/bundle.p12" -passout pass:hats -name "$IDENTITY" 2>&1 >/dev/null)"; then
    echo "openssl pkcs12 failed:" >&2
    echo "$OPENSSL_ERR" >&2
    echo "if this says '-legacy' is unknown, the openssl on PATH is LibreSSL;" >&2
    echo "install OpenSSL 3 (brew install openssl@3) and retry" >&2
    exit 1
fi

# -T names the one binary allowed to use this key without a prompt. `-A` used to
# follow it, and `-A` means "any application": it does not add to that ACL, it
# replaces it with everyone, which hands the private key itself to anything running
# as this user.
#
# What that buys is narrower than it first looks, and NOTES.md says so: `codesign` is
# callable by anything running as you, so this ACL bounds the OPERATION, not the
# caller. Removing `-A` stops direct key access; it does not stop a process from
# asking codesign to sign for it. Bounding the caller means dropping `-T` and
# approving every signature by hand, which is a different product than "run these
# two scripts".
security import "$WORK/bundle.p12" -k "$KEYCHAIN" -P hats \
    -T /usr/bin/codesign >/dev/null

# Imported is not enough: `find-identity -p codesigning` lists nothing until the
# certificate is trusted for code signing. User domain, so no sudo.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "created: $IDENTITY"
security find-identity -v -p codesigning | grep "$IDENTITY" | sed 's/^/  /'
echo
echo "now run ./Build/build-app.sh — it picks the identity up automatically"
