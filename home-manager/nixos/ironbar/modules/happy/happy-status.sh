#!/usr/bin/env bash
# Show Happy daemon status for ironbar widget
# ACTIVE_COLOR is injected by Nix (Stylix base0B green)

if systemctl --user is-active --quiet happy; then
    echo "<span color=\"#${ACTIVE_COLOR}\">󰚩 Happy</span>"
else
    echo "󰚩"
fi
