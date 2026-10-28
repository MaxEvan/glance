#!/bin/sh
# Renders the icon and builds Resources/AppIcon.icns from it.
set -eu
cd "$(dirname "$0")/.."

ICONSET=build/AppIcon.iconset
mkdir -p build Resources
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/AppIcon-1024.png

for size in 16 32 128 256 512; do
  sips -z $size $size build/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double build/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
