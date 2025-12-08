#!/usr/bin/env bash
# Get Logitech mouse battery status for Ironbar custom module
# Uses solaar to query devices connected via Logitech USB receivers

# Get solaar output, suppress stderr (notifications warnings)
OUTPUT=$(solaar show 2>/dev/null)

if [[ -z "$OUTPUT" ]]; then
    exit 0
fi

# Look for battery information in solaar output
# Format: "Battery: XX%, state" or "Battery: XX %"
BATTERY_LINE=$(echo "$OUTPUT" | grep -i "Battery:" | head -1)

if [[ -z "$BATTERY_LINE" ]]; then
    exit 0
fi

# Extract percentage (handles both "50%" and "50 %" formats)
PERCENTAGE=$(echo "$BATTERY_LINE" | grep -oE '[0-9]+\s*%' | tr -d ' %')

if [[ -z "$PERCENTAGE" ]]; then
    exit 0
fi

# Check if charging - show lightning bolt next to mouse icon
# Match "BatteryStatus.CHARGING" but not "BatteryStatus.DISCHARGING"
if echo "$BATTERY_LINE" | grep -q "BatteryStatus\.CHARGING"; then
    echo "󰍽󱐋 ${PERCENTAGE}%"
else
    echo "󰍽 ${PERCENTAGE}%"
fi
