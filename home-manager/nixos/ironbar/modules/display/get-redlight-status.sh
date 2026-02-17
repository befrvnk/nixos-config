#!/usr/bin/env bash
# Get gammastep night light status for ironbar button label

if systemctl --user is-active --quiet gammastep; then
    echo "󰌶 Night Light: ON"
else
    echo "󰌶 Night Light: OFF"
fi
