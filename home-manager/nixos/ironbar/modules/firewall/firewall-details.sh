#!/usr/bin/env bash
# Firewall details for ironbar popup - shows external refused connections
# Filters out local network traffic to highlight potential threats

# Filter for external IPs only (exclude private ranges)
filter_external() {
    grep -v 'SRC=192\.168\.' | \
    grep -v 'SRC=10\.' | \
    grep -v 'SRC=172\.1[6-9]\.' | \
    grep -v 'SRC=172\.2[0-9]\.' | \
    grep -v 'SRC=172\.3[0-1]\.'
}

# Get all refused connections
ALL_REFUSED=$(journalctl -k -b --no-pager 2>/dev/null | grep "refused")

# Get external refused connections
EXTERNAL=$(echo "$ALL_REFUSED" | filter_external)

# Get the last external refused connection
LAST=$(echo "$EXTERNAL" | tail -1)

if [[ -n "$LAST" ]]; then
    # Extract timestamp (first 3 fields: Mon DD HH:MM:SS)
    TIME=$(echo "$LAST" | awk '{print $1, $2, $3}')
    # Extract source IP (IPv4 or IPv6) and port
    SRC=$(echo "$LAST" | grep -oP 'SRC=\K[0-9a-fA-F.:]+' || echo "?")
    SPT=$(echo "$LAST" | grep -oP 'SPT=\K[0-9]+' || echo "?")
    DPT=$(echo "$LAST" | grep -oP 'DPT=\K[0-9]+' || echo "?")

    # Truncate long IPv6 addresses
    if [[ ${#SRC} -gt 20 ]]; then
        SRC="${SRC:0:17}..."
    fi

    echo "Last External"
    echo "───────────────────"
    echo "Time: $TIME"
    echo "From: $SRC:$SPT"
    echo "Port: $DPT"
    echo ""
fi

echo "External by Source"
echo "───────────────────"

# Group external connections by source IP (handles both IPv4 and IPv6)
SOURCES=$(echo "$EXTERNAL" | grep -oP 'SRC=\K[0-9a-fA-F.:]+' | sort | uniq -c | sort -rn)

if [[ -n "$SOURCES" ]]; then
    echo "$SOURCES" | while read count ip; do
        # Truncate long IPv6 addresses for display
        if [[ ${#ip} -gt 20 ]]; then
            ip="${ip:0:17}..."
        fi
        printf "%3s  %s\n" "$count" "$ip"
    done
else
    echo "No external connections"
fi

echo "───────────────────"
EXT_COUNT=$(echo "$EXTERNAL" | grep -c "refused" || echo "0")
LOCAL_COUNT=$(echo "$ALL_REFUSED" | grep -c "refused" || echo "0")
LOCAL_COUNT=$((LOCAL_COUNT - EXT_COUNT))
echo "External: $EXT_COUNT"
echo "Local: $LOCAL_COUNT (filtered)"
