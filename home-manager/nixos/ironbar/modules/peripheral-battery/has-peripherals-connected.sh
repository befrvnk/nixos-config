#!/usr/bin/env bash
# Check if any peripheral batteries are exposed via UPower (mouse, keyboard)
# Exit 0 if connected (show module), exit 1 if not (hide module)
#
# This supports both:
# - Logitech HID++ devices (e.g. hidpp_battery)
# - Standard Bluetooth/HID devices (mouse_dev, keyboard_dev, etc.)
# - Keychron mouse batteries exposed through generic battery_* objects
#   (for example via vendor-specific battery integrations)

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

while IFS= read -r device; do
    [[ -z "$device" ]] && continue

    info=$(upower -i "$device" 2>/dev/null)
    is_peripheral_device "$device" "$info" && exit 0
done < <(upower -e 2>/dev/null)

exit 1
