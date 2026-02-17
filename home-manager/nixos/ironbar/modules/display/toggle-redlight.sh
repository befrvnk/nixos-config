#!/usr/bin/env bash
# Toggle gammastep night light service

if systemctl --user is-active --quiet gammastep; then
    systemctl --user stop gammastep
else
    systemctl --user start gammastep
fi
