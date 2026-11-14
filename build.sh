#!/bin/sh
# Builds FanControl.app: menu bar UI plus the root helper, registered at runtime with SMAppService.
set -e
cd "$(dirname "$0")"
swiftc -O -swift-version 5 Core.swift daemon/main.swift -o fanctld
swiftc -O -swift-version 5 -parse-as-library Core.swift FanApp.swift -o FanControl
rm -rf FanControl.app
mkdir -p FanControl.app/Contents/MacOS FanControl.app/Contents/Resources FanControl.app/Contents/Library/LaunchDaemons
mv FanControl fanctld FanControl.app/Contents/MacOS/
cp Info.plist FanControl.app/Contents/
cp AppIcon.icns FanControl.app/Contents/Resources/
cp com.local.fanctld.plist FanControl.app/Contents/Library/LaunchDaemons/
codesign --force --sign - FanControl.app/Contents/MacOS/fanctld
codesign --force --sign - FanControl.app
echo built FanControl.app
