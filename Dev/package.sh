#!/usr/bin/env bash
# Packages Hats.app for someone else's machine.
#
# Produces a dmg plus an install note. The dmg is signed with the bundle's Developer ID,
# notarized by Apple, stapled and assessed by Gatekeeper before the note is written, so
# this needs the network and the notarytool keychain profile named by HATS_NOTARY_PROFILE
# (default hats-notary). A disk image rather than a zip: it is what a
# person expects to download for a Mac app, it carries the drag-to-Applications gesture
# in the window itself, and `hdiutil` copies the bundle verbatim — signature and
# resource forks intact, which a mangled archive would break with a Gatekeeper message
# that says nothing useful.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="Hats.app"
OUT="dist"

# Before anything tries to read inside it. This check used to sit below the version
# read, so "there is no bundle" came out as a PlistBuddy error about a file that was
# never going to exist.
[[ -d "$APP" ]] || { echo "build it first: ./Build/build-app.sh" >&2; exit 1; }

# The app shows CHANGELOG.md to whoever installs it, so a version missing from it
# reads as a version that changed nothing. This refuses to package rather than
# letting the omission travel; it lives here and not in build-app.sh because a
# developer build should not be blocked by prose, and it is the dmg that reaches
# a person.
./Dev/changelog-check.sh

# No fallback version. A failing PlistBuddy used to yield 0.1.0, so the image went out
# named after a version the bundle does not contain — and the install note asks
# people to quote that version in bug reports.
#
# stderr goes to its own file rather than into the value. Folded in with `2>&1` it
# lands inside $VERSION on any run where PlistBuddy warns and still exits 0, and from
# there into the name of the file being handed to someone else.
PB_ERR="$(mktemp)"
# EXIT does the cleanup; the signal traps only turn the signal into an exit, which runs
# it. A bare `trap '<cleanup>' INT TERM` REPLACES the default action, so Ctrl-C ran the
# cleanup and the script carried on to package a bundle nobody was waiting for.
trap 'rm -f "$PB_ERR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if ! VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$APP/Contents/Info.plist" 2>"$PB_ERR")"; then
    echo "cannot read CFBundleShortVersionString from $APP: $(cat "$PB_ERR")" >&2
    echo "build the app first (./Build/build-app.sh), then package it" >&2
    exit 1
fi
DMG="$OUT/Hats-$VERSION.dmg"

# Nothing user-specific lives in the bundle — credentials are in the keychain and
# the account list in ~/Library/Application Support/Hats — but check rather than assert, because a
# leak here would ship someone's tokens to their friends.
# The pattern has to be an actual address shape. A bare `@` matches machine code
# constantly — the first version of this check found 83 "leaks", every one of them
# a byte sequence like `hC@9`, and refused to package a clean bundle.
# What leaks is the home PATH, not the bare username, and searching for the name
# was the bug: spliced unanchored into the alternation it matched one letter, so on
# an account called `u` or `max` most of the binary matched and packaging refused
# every clean bundle. Making it a fixed string does not help — a one-letter needle
# matches as a substring either way. An embedded absolute home path is how a build
# actually carries an account.
#
# The pattern is written for ANY account rather than this one. `$HOME/` only finds
# what the packaging machine happens to be called, so a bundle built elsewhere — a
# colleague's machine, CI, a container — carries their path straight through the
# check. `/Users/<name>/` is anchored on both sides, so it keeps the property the
# bare username lost. Measured on the real release binary: 0 hits for each pattern.
# The home component excludes only `/`. Excluding whitespace as well looked tidier
# and was a hole: a macOS home directory may carry a space, and `/Users/Build User/`
# is the standard one on a shared build machine, so a bundle built there walked past
# the check. Measured: `/Users/Build User/x` gives 0 hits against the pattern that
# excluded whitespace and 1 against the one that does not. The direction is the one
# stated below — a matcher that is too broad refuses a package and is visible, one
# that is too narrow ships the path.
# The address pattern names what an address CANNOT contain instead of enumerating what
# it may. Two rounds of enumerating went the same way: first four punctuation characters
# of atext, then all twenty — and both were still a list, so every form outside it
# escaped. Measured, each of these gives 0 hits with the atext class and 1 with the
# pattern below: `"user name"@example.com` (quoted local part), `user@[192.0.2.1]`
# (domain literal), and a local part written in Cyrillic. On the real binary both
# patterns give 0, so the width costs nothing here.
#
# A detector is safe when it is too broad: a false positive refuses a package and is
# visible, a false negative ships the address. Requiring a dotted run after the `@` is
# what keeps it off machine code — a bare `@` found 83 byte sequences like `hC@9` — but
# a dot is not the only legal domain side: `user@[IPv6:2001:db8::1]` has none, so a
# bracketed literal is accepted as the alternative. Measured: the IPv6 form goes from 0
# hits to 1, `user@[192.0.2.1]` and `a@b.co` stay at 1, `hC@9` and prose stay at 0, and
# the real binary stays at 0.
LEAK_PATTERN="[^[:space:]@]+@([^[:space:]@]+\.[^[:space:]@]+|\[[^]]+\])"
HOME_PATTERN="/Users/[^/]+/"
if ! STRINGS=$(strings -a "$APP/Contents/MacOS/Hats"); then
    echo "cannot read strings from the bundle binary — refusing to package" >&2
    exit 1
fi
# grep exits 1 when it finds nothing, which is the good case here, and 2 when it
# could not search at all. `|| true` tolerated both, and a failed grep then left an
# empty substitution that arithmetic reads as 0 — the check answering "no leaks"
# because it never looked, which is the one answer it must not invent. Only status 1
# is tolerated; the assignment carries its own `||` so `set -e` stays armed for
# everything else.
# $HOME/ is scanned as well as the generic pattern, not instead of it: a home
# outside /Users — a network account, a container, a relocated account — is not
# matched by /Users/<name>/, and on the machine doing the packaging it is exactly
# the path most likely to be embedded.
# The three patterns overlap, so the hits are collected as LINES and counted once.
# Summing three counts said 2 for a single embedded "/Users/name/x", since $HOME/ and
# /Users/<name>/ both match it — a number larger than the number of leaked strings,
# in the one message a reader uses to judge how bad it is.
EMAIL_RC=0
HOME_RC=0
SELF_RC=0
EMAIL_HITS=$(printf '%s\n' "$STRINGS" | grep -E "$LEAK_PATTERN") || EMAIL_RC=$?
HOME_HITS=$(printf '%s\n' "$STRINGS" | grep -E "$HOME_PATTERN") || HOME_RC=$?
SELF_HITS=$(printf '%s\n' "$STRINGS" | grep -F "$HOME/") || SELF_RC=$?
if (( EMAIL_RC > 1 || HOME_RC > 1 || SELF_RC > 1 )); then
    echo "leak check could not search the bundle (grep exited $EMAIL_RC, $HOME_RC, $SELF_RC)" >&2
    echo "refusing to package on a count nothing measured" >&2
    exit 1
fi
LEAKS=$(printf '%s\n%s\n%s\n' "$EMAIL_HITS" "$HOME_HITS" "$SELF_HITS" \
        | sed '/^[[:space:]]*$/d' | sort -u | wc -l | tr -d '[:space:]')
if [[ "$LEAKS" -gt 0 ]]; then
    echo "refusing to package: found $LEAKS distinct strings carrying a home path or an email address" >&2
    # Quoted with %q rather than wrapped in single quotes by hand: the pattern now
    # contains a quote of its own, which ended the shell string early and printed a
    # command nobody could paste. The one line the reader is told to run has to be
    # the one line that runs.
    echo "inspect with:" >&2
    printf '  strings -a %q | grep -E %q\n' \
        "$APP/Contents/MacOS/Hats" "$LEAK_PATTERN" >&2
    printf '  strings -a %q | grep -E %q\n' \
        "$APP/Contents/MacOS/Hats" "$HOME_PATTERN" >&2
    printf '  strings -a %q | grep -F %q\n' \
        "$APP/Contents/MacOS/Hats" "$HOME/" >&2
    exit 1
fi

# The image goes to Apple for notarization, and only a Developer ID signature with the
# hardened runtime and a timestamp comes back accepted. Without this, a bundle under the
# self-signed certificate would be refused by Apple minutes later instead of here.
if ! SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1)"; then
    echo "cannot read the signature of $APP — refusing to package:" >&2
    echo "$SIGNATURE" >&2
    exit 1
fi
if ! grep -q '^Authority=Developer ID Application: ' <<< "$SIGNATURE"; then
    echo "refusing to package: $APP is not signed with a Developer ID Application certificate." >&2
    echo "Apple notarizes only such a bundle, and without notarization Gatekeeper blocks" >&2
    echo "the first launch of the download." >&2
    echo "fix: build on a machine whose keychain holds one: ./Build/build-app.sh" >&2
    exit 1
fi
if ! grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<< "$SIGNATURE"; then
    echo "refusing to package: $APP is signed without the hardened runtime, which notarization requires." >&2
    echo "fix: ./Build/build-app.sh signs a Developer ID with it" >&2
    exit 1
fi
if ! grep -q '^Timestamp=' <<< "$SIGNATURE"; then
    echo "refusing to package: the signature of $APP carries no timestamp from Apple, which" >&2
    echo "notarization requires." >&2
    echo "fix: ./Build/build-app.sh with the network up" >&2
    exit 1
fi

# The image is signed with the very certificate that signed the bundle, picked by its
# hash. A name would do on most machines, and fails as ambiguous on the one that holds
# a renewed certificate beside the old one under the same name.
CERTS="$(mktemp -d)"
trap 'rm -f "$PB_ERR"; rm -rf "$CERTS"' EXIT
if ! EXTRACT_ERR="$(codesign -d --extract-certificates="$CERTS/cert" "$APP" 2>&1)" \
        || [[ ! -s "$CERTS/cert0" ]]; then
    echo "cannot extract the signing certificate of $APP — refusing to package:" >&2
    echo "$EXTRACT_ERR" >&2
    exit 1
fi
SIGNING_HASH="$(shasum -a 1 "$CERTS/cert0" | awk '{ print toupper($1) }')"
if ! grep -Fq "$SIGNING_HASH" <<< "$(security find-identity -v -p codesigning 2>/dev/null)"; then
    echo "refusing to package: the keychain holds no valid identity for the certificate" >&2
    echo "that signed $APP (SHA-1 $SIGNING_HASH), so the image cannot be signed with it." >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
# Staged in a temp directory so the image holds exactly two things: the app and a
# symlink to /Applications, which is what makes the drag gesture work. Building from
# the repository root instead would put dist/, the notes and everything else inside it.
STAGE="$(mktemp -d)"
PACKAGED=""
trap 'rm -f "$PB_ERR"; rm -rf "$CERTS" "$STAGE"; [[ -n "$PACKAGED" ]] || rm -f "$DMG"' EXIT
ditto "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Hats $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG"

# Signed, notarized, stapled and assessed before the notes below are written. A run that
# stops anywhere before the notes takes the image with it, so an image in dist/ is one
# that passed.
if ! codesign --force --sign "$SIGNING_HASH" --timestamp "$DMG"; then
    echo "signing $DMG failed — codesign's message is above. This signature takes a timestamp" >&2
    echo "from Apple's server, so it needs the network." >&2
    exit 1
fi

NOTARY_PROFILE="${HATS_NOTARY_PROFILE:-hats-notary}"
echo "submitting $DMG to Apple for notarization (keychain profile $NOTARY_PROFILE)."
echo "this waits for Apple's answer; the first submission, on 2026-11-08, took 41 minutes."
NOTARY_RC=0
NOTARY_OUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json)" || NOTARY_RC=$?
NOTARY_STATUS="$(plutil -extract status raw -o - - <<< "$NOTARY_OUT" 2>/dev/null)" || NOTARY_STATUS=""
NOTARY_ID="$(plutil -extract id raw -o - - <<< "$NOTARY_OUT" 2>/dev/null)" || NOTARY_ID=""
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "refusing to hand out $DMG: notarization status is \"${NOTARY_STATUS:-unknown}\"" >&2
    echo "(notarytool exited $NOTARY_RC). Its answer:" >&2
    echo "${NOTARY_OUT:-<empty>}" >&2
    if [[ -n "$NOTARY_ID" ]]; then
        echo "submission id: $NOTARY_ID" >&2
        echo "what Apple found:" >&2
        printf '  xcrun notarytool log %q --keychain-profile %q\n' "$NOTARY_ID" "$NOTARY_PROFILE" >&2
    fi
    exit 1
fi
echo "notarized: submission $NOTARY_ID accepted"

if ! xcrun stapler staple "$DMG"; then
    echo "stapling the notarization ticket to $DMG failed — refusing to hand it out." >&2
    exit 1
fi
if ! xcrun stapler validate "$DMG"; then
    echo "the ticket stapled to $DMG does not validate — refusing to hand it out." >&2
    exit 1
fi

DMG_ASSESSMENT="$(spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1)" || true
if ! grep -Fqx 'source=Notarized Developer ID' <<< "$DMG_ASSESSMENT"; then
    echo "refusing to hand out $DMG: Gatekeeper does not see it as notarized:" >&2
    echo "$DMG_ASSESSMENT" >&2
    exit 1
fi
APP_RC=0
APP_ASSESSMENT="$(spctl --assess --type exec -vv "$APP" 2>&1)" || APP_RC=$?
if (( APP_RC != 0 )) || ! grep -Fqx "$APP: accepted" <<< "$APP_ASSESSMENT"; then
    echo "refusing to hand out $DMG: Gatekeeper does not accept the app inside it:" >&2
    echo "$APP_ASSESSMENT" >&2
    exit 1
fi
echo "Gatekeeper accepts the image and the app: notarized Developer ID"


# Release notes live next to the image, generated from the changelog entry for this
# version. They used to be written by hand before packaging, and packaging wipes the
# output directory — so twice in one evening the file was gone by the time it was
# needed. Generating them here means they cannot be older than the image beside them.
NOTES_FILE="$OUT/RELEASE-NOTES-$VERSION.md"
{
    echo "## Installing"
    echo
    echo "Download \`$(basename "$DMG")\`, open it and drag Hats to Applications."
    echo
    echo "Hats is signed with an Apple Developer ID and notarized by Apple, so it opens on the"
    echo "first launch."
    echo
    echo "Full instructions: [the readme](https://github.com/zyuzka/hats#readme)."
    echo
    echo "---"
    echo
    echo "## What changed"
    echo
    awk -v v="## $VERSION" '$0 ~ "^" v { found = 1; next } found && /^## / { exit } found' CHANGELOG.md
} > "$NOTES_FILE"
PACKAGED=1

echo "packaged:"
echo "  $PWD/$DMG"
echo "  $PWD/$NOTES_FILE"
echo
echo "size: $(du -h "$DMG" | cut -f1)"
