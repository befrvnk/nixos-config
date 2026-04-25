#!/usr/bin/env bash
# Get battery status for connected peripherals (mouse, keyboard) via UPower.
# Supports Logitech HID++, standard Bluetooth/HID devices, and Keychron mice
# that show up as generic battery_* devices.

is_peripheral_device() {
    local device="$1"
    local info="$2"
    local type
    local model

    case "$device" in
        */DisplayDevice|*/line_power_*|*/battery_BAT*|*/ups_*)
            return 1
            ;;
    esac

    if ! echo "$info" | grep -q "percentage:"; then
        return 1
    fi

    type=$(busctl --system get-property org.freedesktop.UPower "$device" org.freedesktop.UPower.Device Type 2>/dev/null | awk '{print $2}')
    case "$type" in
        5|6)
            return 0
            ;;
    esac

    if echo "$device" | grep -qiE "(mouse|keyboard|hidpp_battery|keychron_mouse)"; then
        return 0
    fi

    if echo "$info" | grep -qiE "^[[:space:]]+(mouse|keyboard)$"; then
        return 0
    fi

    model=$(echo "$info" | awk -F: '/^[[:space:]]*model:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}')
    if echo "$model" | grep -qiE "(keychron.*m[0-9]+|logitech.*(mouse|mx|g[0-9]+)|nuphy|air[0-9]+|mouse|keyboard)"; then
        return 0
    fi

    return 1
}

get_device_kind() {
    local device="$1"
    local info="$2"
    local type
    local model

    model=$(echo "$info" | awk -F: '/^[[:space:]]*model:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}')

    # Some vendor-specific battery integrations show up in UPower with a
    # keyboard type even though they belong to a mouse. Prefer explicit model
    # and object-path hints before trusting the UPower type.
    if echo "$device $model" | grep -qiE "(keychron_mouse|keychron.*mouse|keychron.*m[0-9]+)"; then
        echo "mouse"
        return
    fi

    if echo "$device" | grep -qi "mouse"; then
        echo "mouse"
        return
    fi

    if echo "$device" | grep -qi "keyboard"; then
        echo "keyboard"
        return
    fi

    if echo "$info" | grep -qiE "^[[:space:]]+mouse$"; then
        echo "mouse"
        return
    fi

    if echo "$info" | grep -qiE "^[[:space:]]+keyboard$"; then
        echo "keyboard"
        return
    fi

    type=$(busctl --system get-property org.freedesktop.UPower "$device" org.freedesktop.UPower.Device Type 2>/dev/null | awk '{print $2}')
    case "$type" in
        5)
            echo "mouse"
            return
            ;;
        6)
            echo "keyboard"
            return
            ;;
    esac

    if echo "$model" | grep -qiE "(logitech.*(mouse|mx|g[0-9]+)|mouse)"; then
        echo "mouse"
        return
    fi

    if echo "$model" | grep -qiE "(nuphy|air[0-9]+|keyboard)"; then
        echo "keyboard"
        return
    fi

    echo "other"
}

OUTPUT=""

while IFS= read -r device; do
    [[ -z "$device" ]] && continue

    info=$(upower -i "$device" 2>/dev/null)
    is_peripheral_device "$device" "$info" || continue

    percentage=$(echo "$info" | awk '/percentage:/ {gsub(/%/, "", $2); print $2; exit}')
    state=$(echo "$info" | awk '/state:/ {print $2; exit}')
    [[ -z "$percentage" ]] && continue

    case "$(get_device_kind "$device" "$info")" in
        mouse)
            icon="󰍽"
            ;;
        keyboard)
            icon="󰌌"
            ;;
        *)
            icon="󰂀"
            ;;
    esac

    if [[ "$state" == "charging" ]]; then
        icon="${icon}󱐋"
    fi

    [[ -n "$OUTPUT" ]] && OUTPUT="$OUTPUT  "
    OUTPUT="${OUTPUT}${icon} ${percentage}%"
done < <(upower -e 2>/dev/null)

echo "$OUTPUT"
