#!/usr/bin/env bash
# Get notification count for Ironbar

# Get counts from dunstctl
COUNTS=$(dunstctl count)

# Parse the counts
WAITING=$(echo "$COUNTS" | grep "Waiting:" | awk '{print $2}')
DISPLAYED=$(echo "$COUNTS" | grep "Currently displayed:" | awk '{print $3}')
HISTORY=$(echo "$COUNTS" | grep "History:" | awk '{print $2}')

# Use history count (notifications not yet cleared)
TOTAL=$HISTORY

# Choose icon based on count
if [[ $TOTAL -eq 0 ]]; then
    ICON="󰂜"  # Bell outline (no notifications)
else
    ICON="󰂚"  # Bell icon (has notifications)
fi

echo "${ICON} ${TOTAL}"
