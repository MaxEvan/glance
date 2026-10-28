#!/bin/sh
# Builds Glance and installs it into /Applications, then launches it.
set -eu
cd "$(dirname "$0")/.."

./build.sh
pkill -x Glance 2>/dev/null || true
rm -rf /Applications/Glance.app
cp -R build/Glance.app /Applications/

# Each build has a new ad-hoc signature, so clear the stale Accessibility entry
# and let macOS prompt again.
tccutil reset Accessibility com.maxevangeliste.glance >/dev/null 2>&1 || true
open /Applications/Glance.app
echo "Installed /Applications/Glance.app"
