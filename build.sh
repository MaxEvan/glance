#!/bin/sh
# Builds a universal (Apple Silicon + Intel) build/Glance.app from Sources/ with plain swiftc.
set -eu
cd "$(dirname "$0")"

# DEV=1 builds "Glance Dev" with its own app ID, so it gets its own Accessibility
# permission and settings and can run beside the installed Glance.
ID=com.maxevangeliste.glance
APP=build/Glance.app
if [ -n "${DEV:-}" ]; then
  ID=$ID.dev
  APP="build/Glance Dev.app"
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
if [ -n "${DEV:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Glance Dev" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Glance Dev" "$APP/Contents/Info.plist"
fi
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
# so the permission has to be re-granted after every rebuild (Glance Dev clears
# the stale grant itself on launch).
codesign --force --sign - --identifier "$ID" "$APP"

echo "Built $APP"
