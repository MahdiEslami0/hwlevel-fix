#!/system/bin/sh
# Runs very early in boot (before the modem/RIL stack initializes).
# Overriding ro.boot.hwlevel here makes everything that later calls
# getprop ro.boot.hwlevel see P0 (engineering) instead of MP (mass
# production), which is enough for the modem's signed-critical-data
# gate to allow AT+EFUN to succeed. See ../README.md.

MODDIR=${0%/*}
LOG="$MODDIR/last_run.log"

CURRENT=$(resetprop ro.boot.hwlevel)
resetprop ro.boot.hwlevel P0
echo "$(date) : ro.boot.hwlevel was [$CURRENT], forced to [$(resetprop ro.boot.hwlevel)]" >> "$LOG"
