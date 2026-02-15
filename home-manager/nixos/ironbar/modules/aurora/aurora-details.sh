#!/usr/bin/env bash
# Show detailed aurora information in popup
# Includes: Kp index with interpretation, Munich ovation probability, Kp history

# Interpret Kp value for Munich visibility
kp_interpretation() {
    local kp_int=$(printf "%.0f" "$1" 2>/dev/null)
    case "$kp_int" in
        [0-3]) echo "Not visible from Munich" ;;
        4) echo "Unlikely from Munich" ;;
        5) echo "Possible on northern horizon" ;;
        6) echo "Good chance, look north" ;;
        7) echo "Excellent, may be visible overhead" ;;
        *) echo "Extreme storm, likely visible!" ;;
    esac
}

# Classify Kp value
kp_classification() {
    local kp_int=$(printf "%.0f" "$1" 2>/dev/null)
    case "$kp_int" in
        [0-3]) echo "Quiet" ;;
        4) echo "Active" ;;
        5) echo "Minor storm" ;;
        6) echo "Moderate storm" ;;
        7) echo "Strong storm" ;;
        8) echo "Severe storm" ;;
        9) echo "Extreme storm" ;;
        *) echo "Unknown" ;;
    esac
}

# Fetch K-index data
KP_JSON=$(curl -s --connect-timeout 10 "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json" 2>/dev/null)

if [[ -z "$KP_JSON" ]]; then
    echo "Unable to fetch aurora data"
    exit 0
fi

# Latest Kp value and timestamp
LATEST_KP=$(echo "$KP_JSON" | jq -r '.[-1][1] // empty' 2>/dev/null)
LATEST_TIME=$(echo "$KP_JSON" | jq -r '.[-1][0] // empty' 2>/dev/null)

if [[ -z "$LATEST_KP" ]]; then
    echo "Error parsing aurora data"
    exit 0
fi

CLASSIFICATION=$(kp_classification "$LATEST_KP")
VISIBILITY=$(kp_interpretation "$LATEST_KP")

# Extract forecast time (just HH:MM UTC from timestamp)
FORECAST_TIME=""
if [[ -n "$LATEST_TIME" ]]; then
    FORECAST_TIME=$(echo "$LATEST_TIME" | grep -oP '\d{2}:\d{2}' | tail -1)
fi

# Fetch ovation data for Munich probability
OVATION_PROB=""
OVATION_JSON=$(curl -s --connect-timeout 10 "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json" 2>/dev/null)

if [[ -n "$OVATION_JSON" ]]; then
    # Find nearest gridpoint to Munich (lat 48, lon 12)
    OVATION_PROB=$(echo "$OVATION_JSON" | jq '[.coordinates[] | select(.[0] == 12 and .[1] == 48)] | .[0][2] // empty' 2>/dev/null)
fi

# Print header
printf "Aurora Watch\n"
printf "─────────────────\n"
printf "Kp Index: %s (%s)\n" "$LATEST_KP" "$CLASSIFICATION"
printf "Munich visibility: %s\n" "$VISIBILITY"
if [[ -n "$OVATION_PROB" ]]; then
    printf "Ovation probability: %s/29\n" "$OVATION_PROB"
fi
if [[ -n "$FORECAST_TIME" ]]; then
    printf "Forecast: %s UTC\n" "$FORECAST_TIME"
fi

# Print Kp history (last 8 entries = ~24h)
printf "\nRecent Kp History\n"
printf "─────────────────\n"

# Skip header row (index 0), get last 8 entries
HISTORY=$(echo "$KP_JSON" | jq -r '.[-8:][] | select(.[0] != "time_tag") | "\(.[0]) \(.[1])"' 2>/dev/null)

while IFS= read -r line; do
    TIME=$(echo "$line" | grep -oP '\d{2}:\d{2}' | tail -1)
    KP=$(echo "$line" | awk '{print $NF}')
    if [[ -n "$TIME" && -n "$KP" ]]; then
        printf "%s  Kp %s\n" "$TIME" "$KP"
    fi
done <<< "$HISTORY"
