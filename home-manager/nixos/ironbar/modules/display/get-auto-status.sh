#!/usr/bin/env bash
# Get ABM status for ironbar button label

ABM_PATH="/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings"

if [[ -f "$ABM_PATH" ]]; then
    ABM_LEVEL=$(cat "$ABM_PATH" 2>/dev/null || echo "0")
    if [[ "$ABM_LEVEL" -eq 0 ]]; then
        echo "󰹏 ABM: Off"
    else
        echo "󰹏 ABM: On"
    fi
else
    echo "󰹏 ABM: N/A"
fi
