#!/bin/sh
# Packs FanControl.app into FanControl.dmg (drag to Applications). Run ./build.sh first.
set -e
cd "$(dirname "$0")"
rm -rf .dmg-stage FanControl.dmg
mkdir .dmg-stage
cp -R FanControl.app .dmg-stage/
ln -s /Applications .dmg-stage/Applications
hdiutil create -volname "Fan Control" -srcfolder .dmg-stage -ov -format UDZO FanControl.dmg >/dev/null
rm -rf .dmg-stage
echo built FanControl.dmg
