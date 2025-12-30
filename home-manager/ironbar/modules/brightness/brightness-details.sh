#!/usr/bin/env bash
# Brightness details for ironbar popup
# Shows current brightness and ABM status

BRIGHTNESS_PATH="/sys/class/backlight/amdgpu_bl1"
ABM_PATH="/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings"

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

echo "󰃠 Brightness: $PERCENT%"
echo "󰹏 ABM: $ABM_STATUS"
