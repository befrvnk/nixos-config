#!/usr/bin/env bash
# Get detailed battery information for Ironbar popup

# Find the first valid battery device
BATTERY_DEVICE=""
for device in $(upower -e | grep battery); do
    INFO=$(upower -i "$device")
    # Skip if battery shows "should be ignored" or has no power supply
    if echo "$INFO" | grep -q "should be ignored"; then
        continue
    fi
    if echo "$INFO" | grep -q "power supply.*no"; then
        continue
    fi
    BATTERY_DEVICE="$device"
    BATTERY="$INFO"
    break
done

if [[ -z "$BATTERY" ]]; then
    echo "No battery detected"
    exit 0
fi

PERCENTAGE=$(echo "$BATTERY" | grep "percentage:" | awk '{print $2}')
STATE=$(echo "$BATTERY" | grep "state:" | awk '{print $2}')
TIME_TO_EMPTY=$(echo "$BATTERY" | grep "time to empty:" | sed 's/.*time to empty:\s*//')
TIME_TO_FULL=$(echo "$BATTERY" | grep "time to full:" | sed 's/.*time to full:\s*//')
ENERGY=$(echo "$BATTERY" | grep "energy:" | grep -v "energy-" | awk '{print $2, $3}')
ENERGY_FULL=$(echo "$BATTERY" | grep "energy-full:" | awk '{print $2, $3}')
ENERGY_RATE=$(echo "$BATTERY" | grep "energy-rate:" | awk '{print $2, $3}')

# Format output for popup
echo "Battery: ${PERCENTAGE}"
echo "State: ${STATE}"

if [[ -n "$TIME_TO_EMPTY" && "$STATE" == "discharging" ]]; then
    echo "Time remaining: ${TIME_TO_EMPTY}"
elif [[ -n "$TIME_TO_FULL" && "$STATE" == "charging" ]]; then
    echo "Time to full: ${TIME_TO_FULL}"
elif [[ "$STATE" == "fully-charged" ]]; then
    echo "Fully charged"
fi

if [[ -n "$ENERGY" && -n "$ENERGY_FULL" ]]; then
    echo "Energy: ${ENERGY} / ${ENERGY_FULL}"
fi

if [[ -n "$ENERGY_RATE" ]]; then
    echo "Power draw: ${ENERGY_RATE}"
fi
