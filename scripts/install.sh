#!/bin/sh
# Builds MCOverlay and installs it into /Applications, then launches it.
set -eu
cd "$(dirname "$0")/.."

./build.sh
pkill -x MCOverlay 2>/dev/null || true
rm -rf /Applications/MCOverlay.app
cp -R build/MCOverlay.app /Applications/

# Each build has a new ad-hoc signature, so clear the stale Accessibility entry
# and let macOS prompt again.
tccutil reset Accessibility com.maxevangeliste.mcoverlay >/dev/null
open /Applications/MCOverlay.app
echo "Installed /Applications/MCOverlay.app"
