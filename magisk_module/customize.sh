#!/sbin/sh
# shellcheck shell=sh
ui_print "- hwlevel P0 Override"
ui_print "  Forces ro.boot.hwlevel=P0 at every boot so the modem's"
ui_print "  signed-critical-data check stops rejecting AT+EFUN."
ui_print "  Intended for MediaTek Xiaomi devices stuck at hwlevel=MP"
ui_print "  with +ENVSIGERR / no signal after an NVRAM or proinfo wipe."
ui_print "  Read the project README before relying on this in production."
