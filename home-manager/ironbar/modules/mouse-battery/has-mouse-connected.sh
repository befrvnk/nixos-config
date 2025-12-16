#!/usr/bin/env bash
# Check if a Logitech mouse battery is exposed via upower
# Exit 0 if connected (show module), exit 1 if not (hide module)

# Look for HID++ battery devices (Logitech mice/keyboards)
if upower -e 2>/dev/null | grep -q "hidpp_battery"; then
    exit 0  # Mouse connected, show module
else
    exit 1  # No mouse, hide module
fi
