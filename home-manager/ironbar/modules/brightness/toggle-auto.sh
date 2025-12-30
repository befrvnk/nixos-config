#!/usr/bin/env bash
# Toggle ABM (Adaptive Backlight Management) from ironbar popup
# ABM trades color accuracy for power savings

ABM_PATH="/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings"

if [[ -f "$ABM_PATH" ]]; then
    CURRENT=$(cat "$ABM_PATH" 2>/dev/null || echo "0")
    if [[ "$CURRENT" -eq 0 ]]; then
        # ABM off -> enable at level 3 (high savings)
        echo 3 | tee "$ABM_PATH" > /dev/null 2>&1 || true
    else
        # ABM on -> disable for accurate colors
        echo 0 | tee "$ABM_PATH" > /dev/null 2>&1 || true
    fi
fi
