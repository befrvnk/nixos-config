#!/usr/bin/env bash
# Brightness status for ironbar
# Shows brightness percentage and auto-brightness indicator

BRIGHTNESS_PATH="/sys/class/backlight/amdgpu_bl1"
SERVICE="auto-brightness.service"

# Get current brightness percentage
if [[ -f "$BRIGHTNESS_PATH/brightness" ]] && [[ -f "$BRIGHTNESS_PATH/max_brightness" ]]; then
    CURRENT=$(cat "$BRIGHTNESS_PATH/brightness")
    MAX=$(cat "$BRIGHTNESS_PATH/max_brightness")
    PERCENT=$((CURRENT * 100 / MAX))
else
    PERCENT="N/A"
fi

# Check if auto-brightness is active
if systemctl --user is-active "$SERVICE" &>/dev/null; then
    AUTO="A"
else
    AUTO=""
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

# Output with auto indicator
if [[ -n "$AUTO" ]]; then
    echo "$ICON $PERCENT% $AUTO"
else
    echo "$ICON $PERCENT%"
fi
