#!/usr/bin/env bash
# Check if aurora activity is notable (Kp >= 4)
# Returns 0 (show module) if Kp >= 4, 1 (hide) otherwise
# Uses same cache as aurora-status.sh

CACHE_FILE="$HOME/.cache/aurora-kp"

# Read Kp from cache if recent (15 minutes)
if [[ -f "$CACHE_FILE" ]]; then
    CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
    if [[ $CACHE_AGE -lt 900 ]]; then
        KP=$(grep -oP '[\d.]+$' "$CACHE_FILE")
        if [[ -n "$KP" ]]; then
            KP_INT=$(printf "%.0f" "$KP" 2>/dev/null)
            [[ "$KP_INT" -ge 4 ]] && exit 0
            exit 1
        fi
    fi
fi

# Fetch fresh data if cache is stale
KP_JSON=$(curl -s --connect-timeout 5 "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json" 2>/dev/null)

if [[ -z "$KP_JSON" ]]; then
    exit 1
fi

KP=$(echo "$KP_JSON" | jq -r '.[-1][1] // empty' 2>/dev/null)

if [[ -z "$KP" ]]; then
    exit 1
fi

# Update cache for aurora-status.sh
echo "󱁞 Kp ${KP}" > "$CACHE_FILE"

KP_INT=$(printf "%.0f" "$KP" 2>/dev/null)
[[ "$KP_INT" -ge 4 ]] && exit 0
exit 1
