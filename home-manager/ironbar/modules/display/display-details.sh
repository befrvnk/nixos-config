#!/usr/bin/env bash
# Display details for ironbar popup
# Shows brightness, ABM status, and screen idle status

BRIGHTNESS_PATH="/sys/class/backlight/amdgpu_bl1"
ABM_PATH="/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings"
PID_FILE="/tmp/stay-on-inhibit-$USER.pid"

# Get current brightness percentage
if [[ -f "$BRIGHTNESS_PATH/brightness" ]] && [[ -f "$BRIGHTNESS_PATH/max_brightness" ]]; then
    CURRENT=$(cat "$BRIGHTNESS_PATH/brightness")
    MAX=$(cat "$BRIGHTNESS_PATH/max_brightness")
    PERCENT=$((CURRENT * 100 / MAX))
else
    PERCENT="N/A"
fi

# Check ABM status
if [[ -f "$ABM_PATH" ]]; then
    ABM_LEVEL=$(cat "$ABM_PATH" 2>/dev/null || echo "N/A")
    case $ABM_LEVEL in
        0) ABM_STATUS="Off" ;;
        1) ABM_STATUS="Low" ;;
        2) ABM_STATUS="Medium" ;;
        3) ABM_STATUS="High" ;;
        *) ABM_STATUS="$ABM_LEVEL" ;;
    esac
else
    ABM_STATUS="N/A"
fi

# Check screen idle status
AUDIO_PLAYING=false
MANUAL_ON=false
PLAYING_APPS=""

# Check for audio playing via PipeWire (pw-dump + jq)
PLAYING_APPS=$(pw-dump 2>/dev/null | jq -r '.[] | select(.info.props."media.class" == "Stream/Output/Audio" and .info.props."application.name" != null) | .info.props."application.name"' 2>/dev/null | sort -u | head -3 | paste -sd ', ')
if [[ -n "$PLAYING_APPS" ]]; then
    AUDIO_PLAYING=true
fi

# Check for manual stay-on toggle
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    MANUAL_ON=true
fi

# Output brightness and ABM
echo "󰃠 Brightness: $PERCENT%"
echo "󰹏 ABM: $ABM_STATUS"
echo ""
echo "Screen Status"
echo "─────────────────"

# Output screen status
if [[ "$AUDIO_PLAYING" == "true" ]] || [[ "$MANUAL_ON" == "true" ]]; then
    if [[ "$AUDIO_PLAYING" == "true" ]] && [[ -n "$PLAYING_APPS" ]]; then
        echo "󰝚 $PLAYING_APPS"
    fi
    if [[ "$MANUAL_ON" == "true" ]]; then
        echo "󰈈 Manual override"
    fi
    echo "Status: Staying on"
else
    echo "Status: Normal timeout"
fi
