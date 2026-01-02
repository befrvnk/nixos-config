#!/usr/bin/env bash
# Firewall status for ironbar - shows count of refused connections since boot

# Count refused connections from kernel log (since boot)
COUNT=$(journalctl -k -b --no-pager 2>/dev/null | grep -c "refused" || echo "0")

# Firewall/shield icon (Nerd Font)
ICON="󰒃"

if [[ $COUNT -eq 0 ]]; then
    echo "$ICON"
else
    echo "$ICON $COUNT"
fi
