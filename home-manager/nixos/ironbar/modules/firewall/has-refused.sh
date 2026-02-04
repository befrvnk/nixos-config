#!/usr/bin/env bash
# Check if there are refused connections from external IPs (for show_if)
# Filters out local network traffic (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
# Exit 0 = show module, Exit 1 = hide module

COUNT=$(journalctl -k -b --no-pager 2>/dev/null | grep "refused" | \
    grep -v 'SRC=192\.168\.' | \
    grep -v 'SRC=10\.' | \
    grep -v 'SRC=172\.1[6-9]\.' | \
    grep -v 'SRC=172\.2[0-9]\.' | \
    grep -v 'SRC=172\.3[0-1]\.' | \
    wc -l || echo "0")

if [[ $COUNT -gt 0 ]]; then
    exit 0  # External connections found, show module
else
    exit 1  # No external connections, hide module
fi
