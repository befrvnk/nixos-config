#!/usr/bin/env bash
# Get current power profile from power-profiles-daemon
# Maps PPD profile names back to our UI names

PROFILE=$(powerprofilesctl get)

case "$PROFILE" in
    "power-saver")
        echo "low-power"
        ;;
    "balanced")
        echo "balanced"
        ;;
    "performance")
        echo "performance"
        ;;
    *)
        echo "$PROFILE"
        ;;
esac
