#!/usr/bin/env bash
# Toggle Happy daemon via systemd user service

if systemctl --user is-active --quiet happy; then
    systemctl --user stop happy
else
    systemctl --user start happy
fi
