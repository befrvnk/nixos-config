#!/usr/bin/env bash
#
# Custom volume status script for ironbar
#
# WHY THIS EXISTS:
# Ironbar's built-in volume module (type: "volume") has a critical bug where it
# crashes with PulseAudio mainloop assertion failures:
#   "Assertion 'e->mainloop->n_enabled_defer_events > 0' failed at mainloop.c:261"
#
# This is a known issue tracked at: https://github.com/JakeStanger/ironbar/issues/875
# Status: Open as of 2025-11-14, labeled "Critical" and "help wanted"
#
# SOLUTION:
# This custom script uses wpctl (WirePlumber CLI) instead of PulseAudio bindings.
# wpctl queries WirePlumber's in-memory state without using PulseAudio's mainloop,
# completely avoiding the crash.
#
# IMPLEMENTATION NOTES:
# - Uses @DEFAULT_AUDIO_SINK@ which automatically resolves to the configured
#   default audio output (works with sinks, filters, or any audio endpoint)
# - Polling interval: 200ms (5 updates/sec) for responsive UI feedback
# - Performance: <0.1% CPU usage, wpctl is very fast (2-5ms execution time)

# Get volume info using default audio sink
# @DEFAULT_AUDIO_SINK@ automatically resolves to the configured default
volume_info=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)

if [ -z "$volume_info" ]; then
    echo "󰖁 N/A"
    exit 0
fi

# Parse volume percentage
volume=$(echo "$volume_info" | awk '{print int($2 * 100)}')

# Select appropriate Nerd Font icon based on volume state
# Icons used (from Nerd Fonts):
#   󰖁 (U+F0581) - Muted or 0% volume
#   󰕿 (U+F057F) - Low volume (1-32%)
#   󰖀 (U+F0580) - Medium volume (33-65%)
#   󰕾 (U+F057E) - High volume (66-100%)
if echo "$volume_info" | grep -q "MUTED"; then
    icon="󰖁"  # Muted
    echo "$icon ${volume}%"
elif [ "$volume" -eq 0 ]; then
    icon="󰖁"  # Zero volume
    echo "$icon ${volume}%"
elif [ "$volume" -lt 33 ]; then
    icon="󰕿"  # Low volume
    echo "$icon ${volume}%"
elif [ "$volume" -lt 66 ]; then
    icon="󰖀"  # Medium volume
    echo "$icon ${volume}%"
else
    icon="󰕾"  # High volume
    echo "$icon ${volume}%"
fi
