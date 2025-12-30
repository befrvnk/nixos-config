#!/usr/bin/env bash
# Brightness status for ironbar
# Shows brightness percentage

BRIGHTNESS_PATH="/sys/class/backlight/amdgpu_bl1"

# Get current brightness percentage
if [[ -f "$BRIGHTNESS_PATH/brightness" ]] && [[ -f "$BRIGHTNESS_PATH/max_brightness" ]]; then
    CURRENT=$(cat "$BRIGHTNESS_PATH/brightness")
    MAX=$(cat "$BRIGHTNESS_PATH/max_brightness")
    PERCENT=$((CURRENT * 100 / MAX))
else
    PERCENT="N/A"
fi

# Select icon based on brightness level
if [[ "$PERCENT" == "N/A" ]]; then
    ICON="󰃠"
elif [[ $PERCENT -ge 80 ]]; then
    ICON="󰃠"  # bright
elif [[ $PERCENT -ge 50 ]]; then
    ICON="󰃟"  # medium-high
elif [[ $PERCENT -ge 20 ]]; then
    ICON="󰃞"  # medium-low
else
    ICON="󰃝"  # dim
fi

echo "$ICON $PERCENT%"
