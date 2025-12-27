#!/usr/bin/env bash
# Power profile switcher using power-profiles-daemon
# PPD handles platform profile, EPP, and boost coordination automatically

PROFILE="${1:-balanced}"

# Map our UI profile names to PPD profile names
case "$PROFILE" in
    "low-power")
        PPD_PROFILE="power-saver"
        ;;
    "balanced")
        PPD_PROFILE="balanced"
        ;;
    "performance")
        PPD_PROFILE="performance"
        ;;
    *)
        echo "Unknown profile: $PROFILE"
        exit 1
        ;;
esac

powerprofilesctl set "$PPD_PROFILE"
