#!/usr/bin/env bash
# Switch CPU governor between powersave and schedutil on battery

set -euo pipefail

# Check if on AC or battery
get_power_status() {
    local status
    for bat in /sys/class/power_supply/BAT*; do
        if [[ -f "$bat/status" ]]; then
            status=$(cat "$bat/status")
            echo "$status"
            return
        fi
    done
    echo "Unknown"
}

# Get current governor
get_current_governor() {
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    else
        echo "unknown"
    fi
}

# Show usage
usage() {
    echo "Usage: switch-governor [schedutil|powersave|toggle]"
    echo ""
    echo "Switch CPU governor on battery power"
    echo ""
    echo "Options:"
    echo "  schedutil    - Use schedutil governor (performance)"
    echo "  powersave    - Use powersave governor (battery saving)"
    echo "  toggle       - Toggle between schedutil and powersave"
    echo ""
    echo "If no argument is provided, shows current governor"
    exit 1
}

# Main logic
CURRENT_GOVERNOR=$(get_current_governor)

# If no argument, show current governor
if [[ $# -eq 0 ]]; then
    echo "Current CPU Governor: $CURRENT_GOVERNOR"
    exit 0
fi

REQUESTED_GOVERNOR="$1"

# Handle toggle option
if [[ "$REQUESTED_GOVERNOR" == "toggle" ]]; then
    if [[ "$CURRENT_GOVERNOR" == "powersave" ]]; then
        REQUESTED_GOVERNOR="schedutil"
    else
        REQUESTED_GOVERNOR="powersave"
    fi
fi

# Validate governor
if [[ "$REQUESTED_GOVERNOR" != "schedutil" && "$REQUESTED_GOVERNOR" != "powersave" ]]; then
    echo "Error: Invalid governor '$REQUESTED_GOVERNOR'"
    echo "Valid options: schedutil, powersave, toggle"
    usage
fi

# Check power status
POWER_STATUS=$(get_power_status)

if [[ "$POWER_STATUS" != "Discharging" ]]; then
    notify-send -u normal -t 3000 "CPU Governor" "On AC power - using schedutil (managed by TLP)"
    exit 0
fi

# Check if already using requested governor
if [[ "$CURRENT_GOVERNOR" == "$REQUESTED_GOVERNOR" ]]; then
    case "$REQUESTED_GOVERNOR" in
        schedutil)
            notify-send -u low -t 2000 "CPU Governor" "Already using schedutil (Performance)"
            ;;
        powersave)
            notify-send -u low -t 2000 "CPU Governor" "Already using powersave (Battery Saving)"
            ;;
    esac
    exit 0
fi

# Switch governor using sudo with helper script
if sudo set-governor-helper "$REQUESTED_GOVERNOR"; then
    case "$REQUESTED_GOVERNOR" in
        schedutil)
            notify-send -u normal -t 3000 "CPU Governor" "󰓅 Performance Mode\nUsing schedutil governor"
            ;;
        powersave)
            notify-send -u normal -t 3000 "CPU Governor" "󰾅 Battery Saving Mode\nUsing powersave governor"
            ;;
    esac
else
    notify-send -u critical -t 5000 "CPU Governor" "Failed to switch governor"
    exit 1
fi
