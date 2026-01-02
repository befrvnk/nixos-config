#!/usr/bin/env bash
# Firewall details for ironbar popup - shows refused connections grouped by port

# Get the last refused connection with details
LAST=$(journalctl -k -b --no-pager 2>/dev/null | grep "refused" | tail -1)

if [[ -n "$LAST" ]]; then
    # Extract timestamp (first 3 fields: Mon DD HH:MM:SS)
    TIME=$(echo "$LAST" | awk '{print $1, $2, $3}')
    # Extract source IP and port
    SRC=$(echo "$LAST" | grep -oP 'SRC=\K[0-9.]+' || echo "?")
    SPT=$(echo "$LAST" | grep -oP 'SPT=\K[0-9]+' || echo "?")
    DPT=$(echo "$LAST" | grep -oP 'DPT=\K[0-9]+' || echo "?")

    echo "Last Refused"
    echo "───────────────────"
    echo "Time: $TIME"
    echo "From: $SRC:$SPT"
    echo "Port: $DPT"
    echo ""
fi

echo "By Port"
echo "───────────────────"

# Extract DPT (destination port) from refused packet logs and group by port
PORTS=$(journalctl -k -b --no-pager 2>/dev/null | grep "refused" | \
    grep -oP 'DPT=\K[0-9]+' | sort | uniq -c | sort -rn)

if [[ -n "$PORTS" ]]; then
    echo "$PORTS" | while read count port; do
        printf "Port %-6s %s\n" "$port" "$count"
    done
else
    echo "No refused connections"
fi

echo "───────────────────"
TOTAL=$(journalctl -k -b --no-pager 2>/dev/null | grep -c "refused" || echo "0")
echo "Total: $TOTAL (since boot)"
