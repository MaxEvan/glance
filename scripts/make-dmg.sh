#!/bin/sh
# Builds MCOverlay and packages it as build/MCOverlay.dmg with an Applications shortcut.
set -eu
cd "$(dirname "$0")/.."

./build.sh
STAGE=build/dmg
rm -rf "$STAGE" build/MCOverlay.dmg
mkdir -p "$STAGE"
cp -R build/MCOverlay.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname MCOverlay -srcfolder "$STAGE" -ov -format UDZO build/MCOverlay.dmg >/dev/null
rm -rf "$STAGE"
echo "Wrote build/MCOverlay.dmg"
