#!/usr/bin/env bash
# Get device name and capacity for slot N (1-indexed)
# Usage: device-name.sh <slot_number>
# Output: "DeviceName (used/total)" or empty

SLOT=${1:-1}

# Get mounted devices under /run/media/$USER
mapfile -t MOUNTS < <(findmnt -rno TARGET 2>/dev/null | grep "^/run/media/$USER/" | sort)

INDEX=$((SLOT - 1))

if [[ $INDEX -lt ${#MOUNTS[@]} ]]; then
    MOUNT_POINT="${MOUNTS[$INDEX]}"
    NAME=$(basename "$MOUNT_POINT")

    # Get size info
    read -r size used avail <<< "$(df -h "$MOUNT_POINT" 2>/dev/null | awk 'NR==2 {print $2, $3, $4}')"

    if [[ -n "$size" ]]; then
        echo "$NAME ($used/$size)"
    else
        echo "$NAME"
    fi
fi
