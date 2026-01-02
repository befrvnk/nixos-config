#!/usr/bin/env bash
# Returns non-empty string if there are refused connections (for show_if)

COUNT=$(journalctl -k -b --no-pager 2>/dev/null | grep -c "refused" || echo "0")

if [[ $COUNT -gt 0 ]]; then
    echo "1"
fi
