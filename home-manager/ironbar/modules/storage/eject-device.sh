#!/usr/bin/env bash
# Eject device at slot N (1-indexed)
# Usage: eject-device.sh <slot_number>

# Close the popup first
ironbar bar main hide-popup &

SLOT=${1:-1}

# Get mounted devices under /run/media/$USER
mapfile -t MOUNTS < <(findmnt -rno TARGET 2>/dev/null | grep "^/run/media/$USER/" | sort)

INDEX=$((SLOT - 1))

if [[ $INDEX -lt ${#MOUNTS[@]} ]]; then
    MOUNT_POINT="${MOUNTS[$INDEX]}"
    # Get the block device for this mount point
    BLOCK_DEVICE=$(findmnt -rno SOURCE "$MOUNT_POINT")
    if [[ -n "$BLOCK_DEVICE" ]]; then
        udisksctl unmount -b "$BLOCK_DEVICE" &>/dev/null
    fi
fi
