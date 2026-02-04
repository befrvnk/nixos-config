#!/usr/bin/env bash
# Firewall status for ironbar - shows count of external refused connections
# Filters out local network traffic (192.168.x.x, 10.x.x.x, 172.16-31.x.x)

# Count refused connections from external IPs only
COUNT=$(journalctl -k -b --no-pager 2>/dev/null | grep "refused" | \
    grep -v 'SRC=192\.168\.' | \
    grep -v 'SRC=10\.' | \
    grep -v 'SRC=172\.1[6-9]\.' | \
    grep -v 'SRC=172\.2[0-9]\.' | \
    grep -v 'SRC=172\.3[0-1]\.' | \
    wc -l || echo "0")

# Firewall/shield icon (Nerd Font)
ICON="󰒃"

if [[ $COUNT -eq 0 ]]; then
    echo "$ICON"
else
    echo "$ICON $COUNT"
fi
