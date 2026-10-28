#!/bin/sh
# Builds build/MCOverlay.app from Sources/ with plain swiftc (no Xcode project).
set -eu
cd "$(dirname "$0")"

APP=build/MCOverlay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -swift-version 5 -O \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/MCOverlay"

# Ad-hoc signature: macOS ties the Accessibility grant to this exact build,
# so the permission has to be re-granted after every rebuild.
codesign --force --sign - --identifier com.maxevangeliste.mcoverlay "$APP"

echo "Built $APP"
