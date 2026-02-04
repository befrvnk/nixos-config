#!/usr/bin/env bash
# Get WiFi connection status and SSID for Ironbar custom module

# Get active WiFi connection info
WIFI_INFO=$(nmcli -t -f TYPE,STATE,CONNECTION device status | grep "^wifi:connected")

if [[ -n "$WIFI_INFO" ]]; then
    # Get SSID of active connection
    SSID=$(echo "$WIFI_INFO" | cut -d: -f3)

    # Get signal strength
    SIGNAL=$(nmcli -t -f IN-USE,SIGNAL device wifi list | grep "^\*" | cut -d: -f2)

    # Choose icon based on signal strength
    if [[ -n "$SIGNAL" ]]; then
        if [[ $SIGNAL -ge 75 ]]; then
            ICON="󰤨"  # Full signal
        elif [[ $SIGNAL -ge 50 ]]; then
            ICON="󰤥"  # Good signal
        elif [[ $SIGNAL -ge 25 ]]; then
            ICON="󰤢"  # Medium signal
        else
            ICON="󰤟"  # Weak signal
        fi
    else
        ICON="󰤨"  # Default to full if can't determine
    fi

    echo "${ICON} ${SSID}"
else
    # Not connected to WiFi
    echo "󰤮 Disconnected"
fi
