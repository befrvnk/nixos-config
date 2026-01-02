#!/usr/bin/env bash
# Display status for ironbar
# Shows brightness percentage and idle inhibition indicator

BRIGHTNESS_PATH="/sys/class/backlight/amdgpu_bl1"
PID_FILE="/tmp/stay-on-inhibit-$USER.pid"

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

# Check if screen is staying on (audio playing OR manual toggle)
STAYING_ON=false

# Check for audio playing via PipeWire (pw-dump + jq)
AUDIO_STREAMS=$(pw-dump 2>/dev/null | jq -r '[.[] | select(.info.props."media.class" == "Stream/Output/Audio" and .info.props."application.name" != null)] | length' 2>/dev/null)
if [[ "$AUDIO_STREAMS" -gt 0 ]]; then
    STAYING_ON=true
fi

# Check for manual stay-on toggle
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    STAYING_ON=true
fi

# Build output
if [[ "$STAYING_ON" == "true" ]]; then
    echo "$ICON $PERCENT% 󰈈"
else
    echo "$ICON $PERCENT%"
fi
