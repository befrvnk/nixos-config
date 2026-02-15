#!/usr/bin/env bash
# Fetch planetary K-index from NOAA and display aurora status
# Format: icon + Kp value (e.g., "󱁞 Kp 5.3")
# Sends desktop notification when Kp >= 5 (geomagnetic storm)
# Update interval: 10 minutes (600000ms)

CACHE_FILE="$HOME/.cache/aurora-kp"
NOTIFIED_FILE="$HOME/.cache/aurora-notified"

# Read from cache if available and recent (15 minutes)
if [[ -f "$CACHE_FILE" ]]; then
    CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
    if [[ $CACHE_AGE -lt 900 ]]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Fetch K-index data from NOAA
KP_JSON=$(curl -s --connect-timeout 5 "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json" 2>/dev/null)

if [[ -z "$KP_JSON" ]]; then
    # Show cached value if fetch fails
    [[ -f "$CACHE_FILE" ]] && cat "$CACHE_FILE"
    exit 0
fi

# Extract latest Kp value (last element, second field)
KP=$(echo "$KP_JSON" | jq -r '.[-1][1] // empty' 2>/dev/null)

if [[ -z "$KP" ]]; then
    exit 0
fi

OUTPUT="󱁞 Kp ${KP}"
echo "$OUTPUT" > "$CACHE_FILE"
echo "$OUTPUT"

# Send notification for geomagnetic storm (Kp >= 5)
KP_INT=$(printf "%.0f" "$KP" 2>/dev/null)
if [[ "$KP_INT" -ge 5 ]]; then
    SHOULD_NOTIFY=false

    if [[ ! -f "$NOTIFIED_FILE" ]]; then
        SHOULD_NOTIFY=true
    else
        LAST_KP=$(cat "$NOTIFIED_FILE" 2>/dev/null)
        LAST_KP_INT=$(printf "%.0f" "$LAST_KP" 2>/dev/null)
        NOTIFIED_AGE=$(($(date +%s) - $(stat -c %Y "$NOTIFIED_FILE")))

        # Re-notify on escalation or after 6 hours
        if [[ "$KP_INT" -gt "$LAST_KP_INT" ]] || [[ "$NOTIFIED_AGE" -ge 21600 ]]; then
            SHOULD_NOTIFY=true
        fi
    fi

    if [[ "$SHOULD_NOTIFY" == "true" ]]; then
        if [[ "$KP_INT" -ge 7 ]]; then
            URGENCY="critical"
            MSG="Kp ${KP} — Excellent aurora conditions! May be visible overhead from Munich."
        elif [[ "$KP_INT" -ge 6 ]]; then
            URGENCY="critical"
            MSG="Kp ${KP} — Good chance of aurora visible from Munich. Look north!"
        else
            URGENCY="normal"
            MSG="Kp ${KP} — Aurora possible on northern horizon from Munich."
        fi

        dunstify -u "$URGENCY" -i weather-clear-night "Aurora Alert" "$MSG" -r 9200
        echo "$KP" > "$NOTIFIED_FILE"
    fi
else
    # Clear notification flag when storm subsides
    rm -f "$NOTIFIED_FILE"
fi
