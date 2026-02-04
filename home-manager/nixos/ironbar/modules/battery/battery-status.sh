#!/usr/bin/env bash
# Get battery status with dynamic icons for Ironbar custom module

# Find the first valid battery device
BATTERY_DEVICE=""
for device in $(upower -e | grep battery); do
    INFO=$(upower -i "$device")
    # Skip if battery shows "should be ignored" or has 0% and no power supply
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
    echo "󰂑 No battery"
    exit 0
fi

PERCENTAGE=$(echo "$BATTERY" | grep "percentage:" | awk '{print $2}' | tr -d '%')
STATE=$(echo "$BATTERY" | grep "state:" | awk '{print $2}')

# Choose icon based on state and percentage
if [[ "$STATE" == "charging" ]]; then
    # Charging icons
    if [[ $PERCENTAGE -ge 90 ]]; then
        ICON="󰂅"  # Charging full
    elif [[ $PERCENTAGE -ge 70 ]]; then
        ICON="󰂋"  # Charging 80%
    elif [[ $PERCENTAGE -ge 50 ]]; then
        ICON="󰂉"  # Charging 60%
    elif [[ $PERCENTAGE -ge 30 ]]; then
        ICON="󰂇"  # Charging 40%
    elif [[ $PERCENTAGE -ge 10 ]]; then
        ICON="󰢝"  # Charging 20%
    else
        ICON="󰢜"  # Charging low
    fi
elif [[ "$STATE" == "fully-charged" ]]; then
    ICON="󰁹"  # Full
else
    # Discharging icons
    if [[ $PERCENTAGE -ge 90 ]]; then
        ICON="󰁹"  # 100%
    elif [[ $PERCENTAGE -ge 80 ]]; then
        ICON="󰂂"  # 90%
    elif [[ $PERCENTAGE -ge 70 ]]; then
        ICON="󰂁"  # 80%
    elif [[ $PERCENTAGE -ge 60 ]]; then
        ICON="󰂀"  # 70%
    elif [[ $PERCENTAGE -ge 50 ]]; then
        ICON="󰁿"  # 60%
    elif [[ $PERCENTAGE -ge 40 ]]; then
        ICON="󰁾"  # 50%
    elif [[ $PERCENTAGE -ge 30 ]]; then
        ICON="󰁽"  # 40%
    elif [[ $PERCENTAGE -ge 20 ]]; then
        ICON="󰁼"  # 30%
    elif [[ $PERCENTAGE -ge 10 ]]; then
        ICON="󰁻"  # 20%
    else
        ICON="󰁺"  # 10% or less (critical)
    fi
fi

echo "${ICON} ${PERCENTAGE}%"
