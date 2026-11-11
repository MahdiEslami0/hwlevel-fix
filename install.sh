#!/usr/bin/env bash
# Installs the hwlevel P0 override module directly over adb, without needing
# to open the Magisk app. Requires: adb, a rooted device (Magisk) with an
# active root shell, and the device connected with USB debugging authorized.
set -euo pipefail
cd "$(dirname "$0")/magisk_module"

MOD_ID=hwlevel_p0_override
REMOTE_DIR="/data/adb/modules/$MOD_ID"

adb get-state >/dev/null 2>&1 || { echo "No device found over adb."; exit 1; }

echo "Installing $MOD_ID to $REMOTE_DIR ..."
adb shell su -c "mkdir -p $REMOTE_DIR"

for f in module.prop post-fs-data.sh customize.sh; do
  adb push "$f" "/data/local/tmp/$f" >/dev/null
  adb shell su -c "cp /data/local/tmp/$f $REMOTE_DIR/$f"
  adb shell rm -f "/data/local/tmp/$f"
done
adb shell su -c "chmod 755 $REMOTE_DIR/post-fs-data.sh $REMOTE_DIR/customize.sh"

echo "Installed. Reboot the device for it to take effect:"
echo "  adb reboot"
