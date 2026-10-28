#!/bin/sh
# Builds Glance and packages it as build/Glance.dmg with an Applications shortcut.
set -eu
cd "$(dirname "$0")/.."

./build.sh
STAGE=build/dmg
rm -rf "$STAGE" build/Glance.dmg
mkdir -p "$STAGE"
cp -R build/Glance.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Glance -srcfolder "$STAGE" -ov -format UDZO build/Glance.dmg >/dev/null
rm -rf "$STAGE"
echo "Wrote build/Glance.dmg"
