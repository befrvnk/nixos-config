#!/usr/bin/env bash
# Get auto-brightness status for ironbar button label

SERVICE="auto-brightness.service"

if systemctl --user is-active "$SERVICE" &>/dev/null; then
    echo "󰁯 Auto: On"
else
    echo "󰁯 Auto: Off"
fi
