#!/usr/bin/env bash
# Power profile switcher using tuned-adm
# Maps UI profile names to tuned profiles

PROFILE="${1:-balanced}"

case "$PROFILE" in
    "low-power")
        tuned-adm profile framework-battery
        ;;
    "balanced")
        tuned-adm profile framework-ac
        ;;
    "performance")
        tuned-adm profile throughput-performance
        ;;
    *)
        echo "Unknown profile: $PROFILE"
        exit 1
        ;;
esac
