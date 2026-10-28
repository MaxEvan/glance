#!/bin/sh
# Builds a universal (Apple Silicon + Intel) build/MCOverlay.app from Sources/ with plain swiftc.
set -eu
cd "$(dirname "$0")"

APP=build/MCOverlay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O \
    -target "$arch-apple-macos13.0" \
    Sources/*.swift \
    -o "build/MCOverlay-$arch"
done
lipo -create build/MCOverlay-arm64 build/MCOverlay-x86_64 -output "$APP/Contents/MacOS/MCOverlay"
rm build/MCOverlay-arm64 build/MCOverlay-x86_64

# Ad-hoc signature: macOS ties the Accessibility grant to this exact build,
# so the permission has to be re-granted after every rebuild.
codesign --force --sign - --identifier com.maxevangeliste.mcoverlay "$APP"

echo "Built $APP"
