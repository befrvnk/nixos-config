#!/usr/bin/env bash
# Open device at slot N in file manager
# Usage: open-device.sh <slot_number>

SLOT=${1:-1}

# Get mounted devices under /run/media/$USER
mapfile -t MOUNTS < <(findmnt -rno TARGET 2>/dev/null | grep "^/run/media/$USER/" | sort)

INDEX=$((SLOT - 1))

if [[ $INDEX -lt ${#MOUNTS[@]} ]]; then
    MOUNT_POINT="${MOUNTS[$INDEX]}"
    nautilus "$MOUNT_POINT" &
fi

# Close the popup
ironbar bar main hide-popup
