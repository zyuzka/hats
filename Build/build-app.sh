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

swift build -c "$CONFIG"
BIN=".build/$CONFIG/Hats"
[[ -x "$BIN" ]] || { echo "no binary at $BIN" >&2; exit 1; }

rm -rf "$APP" AccSwitch.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hats"
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"
cp Build/Hats.icns "$APP/Contents/Resources/Hats.icns"

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
    <key>HatsUpdateRepository</key>
    <string>zyuzka/hats</string>
    <key>CFBundleDisplayName</key>
    <string>Hats</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

# Signing decides how often the keychain interrogates you.
#
# An ad-hoc signature is derived from the binary, so every rebuild looks like a
# different application and any "Always Allow" granted to the previous build is
# void. A self-signed certificate keeps the identity stable across rebuilds, so
# the grant survives. Create one once:
#
#   Keychain Access → Certificate Assistant → Create a Certificate…
#   Name: Hats Dev · Identity Type: Self Signed Root
#   Certificate Type: Code Signing
#
# Then this picks it up automatically.
IDENTITY="Hats Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --identifier dev.tmk.hats "$APP"
    echo "signed with $IDENTITY (keychain grants survive rebuilds)"
else
    if ! codesign --force --sign - --identifier dev.tmk.hats "$APP"; then
        echo "codesign failed: the bundle is UNSIGNED, not ad-hoc signed." >&2
        echo "an unsigned bundle prompts for keychain access differently and" >&2
        echo "cannot be packaged — fix the signing error before using it." >&2
        exit 1
    fi
    echo "signed ad-hoc — the keychain will re-ask after each rebuild."
    echo "to stop that, create a self-signed 'Code Signing' certificate named '$IDENTITY'"
    echo "in Keychain Access (Certificate Assistant → Create a Certificate)."
fi

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
