#!/usr/bin/env bash
# Check if any peripheral batteries are exposed via upower (mouse, keyboard)
# Exit 0 if connected (show module), exit 1 if not (hide module)

# Look for:
# - hidpp_battery (Logitech mice/keyboards via USB receiver)
# - mouse_hid/mouse_dev (standard HID mice, including Bluetooth)
# - keyboard_hid/keyboard_dev (standard HID keyboards, including Bluetooth)
if upower -e 2>/dev/null | grep -qE "(hidpp_battery|mouse_hid|mouse_dev|keyboard_hid|keyboard_dev)"; then
    exit 0  # Peripheral connected, show module
else
    exit 1  # No peripherals, hide module
fi
