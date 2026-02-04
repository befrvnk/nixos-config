#!/usr/bin/env bash
# Get eject icon for slot N if device exists
# Usage: device-eject.sh <slot_number>
# Output: "⏏" or empty

SLOT=${1:-1}

# Get mounted devices under /run/media/$USER
mapfile -t MOUNTS < <(findmnt -rno TARGET 2>/dev/null | grep "^/run/media/$USER/" | sort)

INDEX=$((SLOT - 1))

if [[ $INDEX -lt ${#MOUNTS[@]} ]]; then
    echo "⏏"
fi
