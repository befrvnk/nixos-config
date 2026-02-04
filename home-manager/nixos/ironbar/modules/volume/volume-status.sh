#!/usr/bin/env bash
#
# Volume status reader for ironbar (event-driven architecture)
#
# WHY THIS EXISTS:
# This script simply reads from a cache file that is updated by volume-ctl.sh
# whenever the user changes volume via keybindings. This eliminates all dbus
# polling overhead - no wpctl calls, no pipewire queries.
#
# ARCHITECTURE:
# 1. User presses volume key (XF86AudioRaiseVolume, etc.)
# 2. Niri calls volume-ctl.sh which:
#    - Calls swayosd-client for OSD display
#    - Updates ~/.cache/volume-status with current volume
# 3. Ironbar polls this script every 1000ms
# 4. This script just reads the cache file (instant, no dbus)
#
# PREVIOUS APPROACH (problematic):
# Each wpctl call generated ~185 dbus messages due to pipewire Realtime portal
# queries. At 5 calls/sec (200ms polling), this was 925 dbus messages/sec.
#
# NEW APPROACH:
# wpctl is only called when user actually changes volume (~occasional).
# Ironbar polling just reads a file - effectively zero overhead.
#
# FALLBACK:
# If cache file doesn't exist (first boot, cache cleared), show N/A.
# The cache is initialized on graphical session start via niri startup.
#

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/volume-status"

if [ -f "$CACHE_FILE" ]; then
    cat "$CACHE_FILE"
else
    # Cache not initialized yet
    echo "󰖁 N/A"
fi
