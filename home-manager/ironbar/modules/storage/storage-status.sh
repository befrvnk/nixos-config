#!/usr/bin/env bash
# Show mounted removable devices for ironbar bar display
# Output: icon + device name(s) or count

# Get mounted devices under /run/media/$USER
mapfile -t MOUNTS < <(findmnt -rno TARGET 2>/dev/null | grep "^/run/media/$USER/" | sort)

COUNT=${#MOUNTS[@]}

if [[ $COUNT -eq 0 ]]; then
    exit 0
fi

# Storage icon (nf-md-harddisk)
ICON="󰋊"

if [[ $COUNT -eq 1 ]]; then
    # Single device: show name
    NAME=$(basename "${MOUNTS[0]}")
    echo "$ICON $NAME"
else
    # Multiple devices: show count
    echo "$ICON $COUNT devices"
fi
