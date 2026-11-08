#!/usr/bin/env bash
# Builds Hats.app.
#
# A bare `swift run` binary cannot take keyboard focus on macOS, so text fields
# in its dialogs stay unusable. A real bundle fixes that, and it is also what
# lets the keychain remember its access decision instead of prompting per read.
set -euo pipefail

# Stopping the app stops the gateway, and a Claude Code session started from a shell
# that had read the gateway block keeps ANTHROPIC_BASE_URL in its own environment —
# nothing outside that session can take it back out. So the build breaks those
# sessions, and on 2026-09-02 it broke three of them because the script was run to
# check one line of output rather than to produce a build.
#
# Which sessions those are is decided in gateway-session-probe.sh, which exists so
# that this guard and the app read a gateway address the same way; it carries the
# reasoning and the two deliberate differences from the Swift. It is sourced by an
# absolute path because the cd below has not happened yet.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gateway-session-probe.sh"

refuseIfTheBuildWouldBreakASession() {
    buildMayStopSessions && return 0
    pgrep -x 'Hats|Hats' >/dev/null 2>&1 || return 0
    local atRisk
    atRisk="$(sessionsTheBuildWouldBreak)"
    if [[ -n "$atRisk" ]]; then
        echo "build-app.sh: refusing to stop the running app." >&2
        echo "" >&2
        echo "These Claude Code sessions reach Claude through the gateway and would stop" >&2
        echo "working the moment it goes down:" >&2
        indentEachLine "$(describeAtRisk "$atRisk")" >&2
        echo "" >&2
        echo "Either finish or quit them, or build anyway with" >&2
        echo "  HATS_BUILD_MAY_STOP_SESSIONS=1 ./Build/build-app.sh" >&2
        echo "" >&2
        echo "It is not the default because the sessions belong to whoever is using them," >&2
        echo "and a build is usually not worth one of them." >&2
        exit 1
    fi
}

# Asked twice on purpose: once here so a refusal costs nothing, and once again
# immediately before the kill, because the app can be launched while the build
# runs and the early answer would be stale by then.
refuseIfTheBuildWouldBreakASession


cd "$(dirname "$0")/.."
APP="Hats.app"
CONFIG="${1:-release}"

# The app updates itself through Sparkle, which SwiftPM builds as a framework beside the
# binary. Everything Sparkle needs from the bundle sits in this script: the rpath here, the
# framework copied in below, the SU keys in the Info.plist and the signing of its parts,
# innermost first, further down.
#
# SwiftPM does not give an executable the rpath an app bundle needs, so the binary would
# look for Sparkle.framework everywhere except Contents/Frameworks and fail to launch.
swift build -c "$CONFIG" -Xlinker -rpath -Xlinker @executable_path/../Frameworks
BIN=".build/$CONFIG/Hats"
[[ -x "$BIN" ]] || { echo "no binary at $BIN" >&2; exit 1; }
SPARKLE_BUILT=".build/$CONFIG/Sparkle.framework"
[[ -d "$SPARKLE_BUILT" ]] || { echo "no Sparkle.framework at $SPARKLE_BUILT" >&2; exit 1; }
LOAD_COMMANDS="$(otool -l "$BIN")"
if ! grep -Fq 'path @executable_path/../Frameworks ' <<< "$LOAD_COMMANDS"; then
    echo "$BIN carries no @executable_path/../Frameworks rpath, so the bundle could not load Sparkle." >&2
    exit 1
fi

rm -rf "$APP" AccSwitch.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Hats"
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"
cp Build/Hats.icns "$APP/Contents/Resources/Hats.icns"

# ditto keeps the framework's internal symlinks and permissions, which Sparkle's own
# installation notes require. The XPC services are for sandboxed apps; Hats is not one, and
# Sparkle's documentation lets a non-sandboxed app remove them. They go before signing,
# because removing a part afterwards breaks the framework's signature.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_BUILT" "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
SPARKLE_PARTS=(
    "$SPARKLE/Versions/B/Autoupdate"
    "$SPARKLE/Versions/B/Updater.app"
    "$SPARKLE"
)

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Hats</string>
    <key>CFBundleIdentifier</key>
    <string>dev.tmk.hats</string>
    <key>CFBundleName</key>
    <string>Hats</string>
    <key>CFBundleIconFile</key>
    <string>Hats</string>
    <key>SUFeedURL</key>
    <string>https://github.com/zyuzka/hats/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>SJ+SqF6QG8EgeJOwpnJNTLw/rarByx+Ef4VJovZSl7w=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>21600</integer>
    <key>SUAllowsAutomaticUpdates</key>
    <false/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
    <key>SURequireSignedFeed</key>
    <true/>
    <key>CFBundleDisplayName</key>
    <string>Hats</string>
    <key>CFBundleShortVersionString</key>
    <string>0.4.1</string>
    <key>CFBundleVersion</key>
    <string>0.4.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- Menu-bar only: no Dock icon, no main window. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Sparkle compares CFBundleVersion with the feed's sparkle:version, so it has to grow with every
# release; it is kept equal to the version a person sees. A bundle without the public key would
# start an updater that refuses every update it finds, so the build stops instead.
PUBLIC_ED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null)" \
    || PUBLIC_ED_KEY=""
if [[ -z "${PUBLIC_ED_KEY//[[:space:]]/}" ]]; then
    echo "SUPublicEDKey is empty in $APP/Contents/Info.plist: the updater could not check any update." >&2
    echo "print the key with: generate_keys --account dev.tmk.hats -p" >&2
    exit 1
fi

# A trial build can point the updater at a feed served from this machine, to watch one build
# update another without publishing anything. Only such a build carries the transport
# exception that lets Sparkle read plain http from localhost; Dev/package.sh refuses to
# package a bundle whose feed is not the published one or which carries the exception.
if [[ -n "${HATS_UPDATE_FEED_URL:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $HATS_UPDATE_FEED_URL" "$APP/Contents/Info.plist"
    if [[ "$HATS_UPDATE_FEED_URL" =~ ^http://(127\.0\.0\.1|localhost)(:[0-9]+)?/ ]]; then
        /usr/libexec/PlistBuddy \
            -c 'Add :NSAppTransportSecurity dict' \
            -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' \
            "$APP/Contents/Info.plist"
    fi
    echo "TRIAL BUILD: the updater reads $HATS_UPDATE_FEED_URL; Dev/package.sh will refuse this bundle."
fi

# Signing decides whether a downloaded copy opens on its first launch, and whether
# macOS treats a rebuild as the same app.
#
# The identity is taken in this order, and the build prints which one it used:
#
#   1. HATS_SIGNING_IDENTITY — a full name, or the 40-character hash that
#      `security find-identity -v -p codesigning` prints; `-` asks for ad-hoc.
#      A value that names no valid identity stops the build instead of falling
#      through to the next step.
#   2. The first valid "Developer ID Application:" identity in the keychain. Only
#      this one, once Dev/package.sh has had the image notarized, lets a download
#      open without a detour through Privacy & Security.
#   3. "Hats Dev", the self-signed certificate ./Build/setup-signing.sh creates.
#   4. Ad-hoc.
#
# A Developer ID signature is made with the hardened runtime and a timestamp from
# Apple, because notarization refuses a bundle that lacks either. A signing that
# fails here — no network to the timestamp server is the usual cause — stops the
# build rather than leaving a signature the release cannot use. Without the network,
# HATS_SIGNING_IDENTITY="Hats Dev" builds with the self-signed certificate instead.
#
# Ad-hoc is last because its signature is derived from the binary: every rebuild
# looks like a different application, and any "Always Allow"
# given to the previous build is void. Both certificates keep the identity stable
# across rebuilds, so the grants survive.
. Build/signing-identity.sh
AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
chooseSigningIdentity

# Sparkle's parts are signed one by one, innermost first, with the same identity and flags
# as the app, and the app last. --deep would sign them all alike in an order nobody chose,
# which Sparkle's documentation warns against.
signEveryPart() {
    local part
    for part in "${SPARKLE_PARTS[@]}"; do
        codesign --force "$@" "$part" || return 1
    done
    codesign --force "$@" --identifier dev.tmk.hats "$APP"
}

verifyEveryPart() {
    local part
    for part in "${SPARKLE_PARTS[@]}" "$APP"; do
        if ! codesign --verify --strict --verbose=2 "$part"; then
            echo "$part does not pass codesign --verify --strict after signing with $IDENTITY_NAME." >&2
            exit 1
        fi
    done
}

signForRelease() {
    if ! signEveryPart --options runtime --timestamp --sign "$IDENTITY"; then
        echo "codesign with $IDENTITY_NAME failed — its own message is above — and the build stops" >&2
        echo "rather than sign the bundle some other way. This signature takes a timestamp from" >&2
        echo "Apple's server, so it needs the network. Without the network, the self-signed" >&2
        echo "certificate from ./Build/setup-signing.sh builds a bundle that cannot be packaged:" >&2
        echo "  HATS_SIGNING_IDENTITY=\"Hats Dev\" ./Build/build-app.sh" >&2
        exit 1
    fi
    verifyEveryPart
    local part details
    for part in "${SPARKLE_PARTS[@]}" "$APP"; do
        details="$(codesign -dv --verbose=2 "$part" 2>&1)"
        if ! grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<< "$details" \
                || ! grep -q '^Timestamp=' <<< "$details"; then
            echo "signed with $IDENTITY_NAME, but $part lacks the hardened runtime or Apple's timestamp:" >&2
            indentEachLine "$details" >&2
            echo "notarization refuses such a bundle, so the build does not hand it over." >&2
            exit 1
        fi
    done
    echo "signed with $IDENTITY_NAME: hardened runtime and Apple's timestamp, ready for notarization"
}

signWithCertificate() {
    if ! signEveryPart --sign "$IDENTITY"; then
        echo "codesign with $IDENTITY_NAME failed — fix the signing error before using the bundle." >&2
        exit 1
    fi
    verifyEveryPart
    echo "signed with $IDENTITY_NAME (grants survive rebuilds; Gatekeeper will block a download)"
}

signAdHoc() {
    if ! signEveryPart --sign -; then
        echo "codesign failed: the bundle is UNSIGNED, not ad-hoc signed." >&2
        echo "an unsigned bundle prompts for keychain access differently and" >&2
        echo "cannot be packaged — fix the signing error before using it." >&2
        exit 1
    fi
    verifyEveryPart
    echo "signed ad-hoc — the keychain will re-ask after each rebuild."
    echo "to stop that, run ./Build/setup-signing.sh once and build again."
}

case "$IDENTITY_NAME" in
    "Developer ID Application: "*) signForRelease ;;
    ad-hoc) signAdHoc ;;
    *) signWithCertificate ;;
esac

# Re-register with LaunchServices, and stop the running copy first.
#
# Without this, `open` on a rebuilt bundle fails with -600 (procNotFound):
# LaunchServices keeps its own record of a bundle id and serves the stale one,
# which is neither the bundle on disk nor anything the user can see. Measured
# 2026-08-20 — the app launched fine when its binary was run directly and refused
# to launch through `open`, which reads as a broken build rather than a cache.
# A TERM is a normal quit since QuitOnSignal: the app stops the gateway and takes its
# block back out of the shell profile before it exits. Wait for that to finish — a new
# copy launched while the old one still holds the port fails its bind and withdraws the
# block itself. Only a copy that has ignored TERM for five seconds is killed outright.
# The process is matched under both of its names: a copy built before the rename is still
# called Hats, still holds the gateway port, and would make the new copy's bind fail.
refuseIfTheBuildWouldBreakASession
if pkill -x 'Hats|Hats' 2>/dev/null; then
    for _ in $(seq 1 50); do
        pgrep -x 'Hats|Hats' >/dev/null || break
        sleep 0.1
    done
    pkill -KILL -x 'Hats|Hats' 2>/dev/null || true
fi
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$PWD/$APP"

echo "built $PWD/$APP"
echo "run:  open $PWD/$APP"
