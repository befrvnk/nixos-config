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

# Check if audio is playing via wpctl
# >2 active channels means actual audio (baseline is 2 speaker outputs)
is_audio_playing() {
    local status=$(wpctl status 2>/dev/null)
    # If [paused] exists, media is paused
    if echo "$status" | grep -q '\[paused\]'; then
        return 1
    fi
    # >2 active channels means actual audio playing
    [ "$(echo "$status" | grep -c '\[active\]')" -gt 2 ]
}

# Check if screen should stay on (audio playing OR manual toggle)
STAYING_ON=false

if is_audio_playing; then
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
