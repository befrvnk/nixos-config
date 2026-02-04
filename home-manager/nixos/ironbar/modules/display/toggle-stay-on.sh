#!/usr/bin/env bash
# Toggle manual stay-on mode for display
# Uses systemd-inhibit to prevent screen lock/off

PID_FILE="/tmp/stay-on-inhibit-$USER.pid"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    # Currently on, turn off
    kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
else
    # Currently off, turn on
    # Start systemd-inhibit in background
    systemd-inhibit --what=idle --who="Ironbar" --why="Manual stay-on" sleep infinity &
    echo $! > "$PID_FILE"
fi
