#!/bin/sh
# Builds a universal (Apple Silicon + Intel) build/Glance.app from Sources/ with plain swiftc.
set -eu
cd "$(dirname "$0")"

APP=build/Glance.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# Release builds pass VERSION (e.g. 1.2.0) to stamp the bundle.
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O \
    -target "$arch-apple-macos14.0" \
    Sources/*.swift \
    -o "build/Glance-$arch"
done
lipo -create build/Glance-arm64 build/Glance-x86_64 -output "$APP/Contents/MacOS/Glance"
rm build/Glance-arm64 build/Glance-x86_64

# Ad-hoc signature: macOS ties the Accessibility grant to this exact build,
# so the permission has to be re-granted after every rebuild.
codesign --force --sign - --identifier com.maxevangeliste.glance "$APP"

echo "Built $APP"
