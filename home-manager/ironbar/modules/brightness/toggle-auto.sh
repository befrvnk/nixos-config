#!/usr/bin/env bash
# Toggle auto-brightness from ironbar popup
# This is a simplified version that just toggles the service

SERVICE="auto-brightness.service"
ABM_PATH="/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings"

if systemctl --user is-active "$SERVICE" &>/dev/null; then
    # Currently enabled -> disable
    systemctl --user stop "$SERVICE"
    echo 0 | tee "$ABM_PATH" > /dev/null 2>&1 || true
else
    # Currently disabled -> enable
    systemctl --user start "$SERVICE"
    # ABM will be restored by power-profile-auto based on AC/battery
fi
