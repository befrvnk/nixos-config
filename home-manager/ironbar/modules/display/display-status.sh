#!/usr/bin/env bash
# Display status for ironbar
# Shows brightness percentage and idle inhibition indicator

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

# Check if stasis is currently inhibiting idle (manual toggle, app inhibitor, or media)
STATUS=$(stasis info --json 2>/dev/null)
STAYING_ON=false

# Check for various possible field names indicating inhibition
if echo "$STATUS" | grep -qE '"(manually_inhibited|paused|inhibited|idle_inhibited)":\s*true'; then
    STAYING_ON=true
fi

# Build output
if [[ "$STAYING_ON" == "true" ]]; then
    echo "$ICON $PERCENT% 󰈈"
else
    echo "$ICON $PERCENT%"
fi
