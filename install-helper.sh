#!/bin/sh
# Installs the root helper as a boot-time launchd service. Run: sudo ./install-helper.sh
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
R="$(cd "$(dirname "$0")" && pwd)/FanControl.app/Contents/Resources"
BIN=/Library/PrivilegedHelperTools/com.local.fanctld
PLIST=/Library/LaunchDaemons/com.local.fanctld.plist
launchctl bootout system/com.local.fanctld 2>/dev/null || true
mkdir -p /Library/PrivilegedHelperTools
install -o root -g wheel -m 755 "$R/fanctld" "$BIN"
install -o root -g wheel -m 644 "$R/com.local.fanctld.plist" "$PLIST"
rm -f /usr/local/libexec/fanctld   # location used by earlier versions
launchctl bootstrap system "$PLIST"
sleep 1
echo "helper:" "$(echo mode | nc -U /var/run/fanctl.sock)"
