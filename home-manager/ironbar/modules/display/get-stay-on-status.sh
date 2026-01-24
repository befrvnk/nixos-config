#!/usr/bin/env bash
# Get manual stay-on status for ironbar button label

PID_FILE="/tmp/stay-on-inhibit-$USER.pid"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "󰈈 Stay On: ON"
else
    echo "󰈈 Stay On: OFF"
fi
