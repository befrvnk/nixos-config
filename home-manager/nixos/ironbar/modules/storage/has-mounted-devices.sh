#!/usr/bin/env bash
# Check if any removable devices are mounted
# Exit 0 if mounted (show module), exit 1 if not (hide module)

# Look for mounts under /run/media/$USER (where udiskie mounts removable devices)
if findmnt -rno TARGET 2>/dev/null | grep -q "^/run/media/$USER/"; then
    exit 0  # Devices mounted, show module
else
    exit 1  # No devices, hide module
fi
