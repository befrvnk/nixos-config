#!/usr/bin/env bash
# Check if a Logitech mouse is connected via USB receiver
# Exit 0 if connected (show module), exit 1 if not (hide module)

# Get solaar output, suppress stderr
OUTPUT=$(solaar show 2>/dev/null)

# Check if there's battery information (indicates a device is connected)
if echo "$OUTPUT" | grep -qi "Battery:"; then
    exit 0  # Mouse connected, show module
else
    exit 1  # No mouse, hide module
fi
