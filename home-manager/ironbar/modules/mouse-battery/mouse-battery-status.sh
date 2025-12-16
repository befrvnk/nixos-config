#!/usr/bin/env bash
# Get Logitech mouse battery status via upower
# Uses HID++ battery devices exposed by the kernel driver

# Find HID++ battery device (Logitech mice/keyboards)
DEVICE=$(upower -e 2>/dev/null | grep "hidpp_battery" | head -1)

if [[ -z "$DEVICE" ]]; then
    exit 0
fi

# Get battery info
INFO=$(upower -i "$DEVICE" 2>/dev/null)
PERCENTAGE=$(echo "$INFO" | grep "percentage:" | awk '{print $2}' | tr -d '%')
STATE=$(echo "$INFO" | grep "state:" | awk '{print $2}')

if [[ -z "$PERCENTAGE" ]]; then
    exit 0
fi

# Show charging indicator - lightning bolt next to mouse icon
if [[ "$STATE" == "charging" ]]; then
    echo "󰍽󱐋 ${PERCENTAGE}%"
else
    echo "󰍽 ${PERCENTAGE}%"
fi
