#!/usr/bin/env bash
# Format notification history for display in Ironbar popup

# Get history from dunstctl in JSON format
HISTORY=$(dunstctl history)

# Check if there are any notifications using jq
if ! echo "$HISTORY" | jq -e '.data[0] | length > 0' > /dev/null 2>&1; then
    echo "No notifications"
    exit 0
fi

# Parse and format the last 10 notifications
echo "$HISTORY" | jq -r '.data[0][:10][] |
    "\(.appname.data // "Unknown"): \(.summary.data // "No summary")" +
    (if .body.data != "" then "\n\(.body.data)" else "" end) +
    "\n---"'
