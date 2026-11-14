#!/bin/sh
# Installs the root helper as a boot-time launchd service. Run: sudo ./install-helper.sh
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
R="$(cd "$(dirname "$0")" && pwd)/FanControl.app/Contents/Resources"
mkdir -p /usr/local/libexec
cp "$R/fanctld" /usr/local/libexec/fanctld
chmod 755 /usr/local/libexec/fanctld
cp "$R/com.local.fanctld.plist" /Library/LaunchDaemons/
chown root:wheel /Library/LaunchDaemons/com.local.fanctld.plist
launchctl bootout system/com.local.fanctld 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.local.fanctld.plist
sleep 1
echo "helper:" "$(echo mode | nc -U /var/run/fanctl.sock)"
