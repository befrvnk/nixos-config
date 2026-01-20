#!/usr/bin/env bash
# Get battery status for connected peripherals (mouse, keyboard) via upower
# Displays each device with appropriate icon and percentage

OUTPUT=""

# Process all peripheral battery devices
while IFS= read -r DEVICE; do
    [[ -z "$DEVICE" ]] && continue

    # Get battery info
    INFO=$(upower -i "$DEVICE" 2>/dev/null)
    PERCENTAGE=$(echo "$INFO" | grep "percentage:" | awk '{print $2}' | tr -d '%')
    STATE=$(echo "$INFO" | grep "state:" | awk '{print $2}')

    [[ -z "$PERCENTAGE" ]] && continue

    # Determine device type from path and choose appropriate icon
    # 󰍽 = mouse, 󰌌 = keyboard
    if echo "$DEVICE" | grep -qE "(mouse|hidpp.*mouse)"; then
        ICON="󰍽"
    elif echo "$DEVICE" | grep -qE "(keyboard|hidpp.*keyboard)"; then
        ICON="󰌌"
    elif echo "$DEVICE" | grep -q "hidpp_battery"; then
        # Logitech HID++ device - check model name for type
        MODEL=$(echo "$INFO" | grep "model:" | awk '{$1=""; print $0}' | xargs)
        if echo "$MODEL" | grep -qi "mouse\|mx\|m[0-9]"; then
            ICON="󰍽"
        elif echo "$MODEL" | grep -qi "keyboard\|k[0-9]\|nuphy"; then
            ICON="󰌌"
        else
            # Default to mouse for unknown Logitech devices (most common)
            ICON="󰍽"
        fi
    else
        # Unknown device type - use generic battery icon
        ICON="󰂀"
    fi

    # Add charging indicator (lightning bolt)
    if [[ "$STATE" == "charging" ]]; then
        ICON="${ICON}󱐋"
    fi

    # Append to output with space separator
    [[ -n "$OUTPUT" ]] && OUTPUT="$OUTPUT  "
    OUTPUT="${OUTPUT}${ICON} ${PERCENTAGE}%"
done < <(upower -e 2>/dev/null | grep -E "(hidpp_battery|mouse_hid|mouse_dev|keyboard_hid|keyboard_dev)")

# Print combined output
echo "$OUTPUT"
