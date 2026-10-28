#!/bin/sh
# Checks a built Glance.dmg on the current machine: contents, signature,
# architectures, and that the app launches and keeps running.
# Usage: scripts/smoke-test.sh build/Glance.dmg
set -eu
DMG=$1
MOUNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
trap '[ -n "${PID:-}" ] && kill "$PID" 2>/dev/null; hdiutil detach "$MOUNT" -quiet || true' EXIT

APP="$MOUNT/Glance.app"
echo "macOS $(sw_vers -productVersion) on $(uname -m)"

test -L "$MOUNT/Applications" || { echo "Missing Applications shortcut in DMG"; exit 1; }
codesign --verify --strict "$APP"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Glance")
echo "Architectures: $ARCHS"
case "$ARCHS" in *arm64*) ;; *) echo "Missing arm64"; exit 1 ;; esac
case "$ARCHS" in *x86_64*) ;; *) echo "Missing x86_64"; exit 1 ;; esac
echo "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# Launch the native slice and make sure it stays up and reaches its startup log line.
LOG="$HOME/Library/Logs/Glance.log"
BEFORE=$(cat "$LOG" 2>/dev/null | wc -l)
"$APP/Contents/MacOS/Glance" >/dev/null 2>&1 &
PID=$!
sleep 5
kill -0 "$PID" 2>/dev/null || { echo "Glance exited during startup"; exit 1; }
tail -n +"$((BEFORE + 1))" "$LOG" | grep -q "Glance launched" || { echo "Startup log line missing"; exit 1; }
kill "$PID"; wait "$PID" 2>/dev/null || true; PID=
echo "Smoke test passed"
