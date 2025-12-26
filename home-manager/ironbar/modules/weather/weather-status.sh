#!/usr/bin/env bash
# Fetch current weather from wttr.in (auto-detect location)
# Format: Nerd Font icon + temperature (e.g., "󰖙 22°C")
# Uses monochrome icons to match other bar modules
# Update interval: 10 minutes (600000ms)

CACHE_FILE="$HOME/.cache/weather-status"

# Map wttr.in weather codes to Nerd Font weather icons
get_weather_icon() {
    local code="$1"
    case "$code" in
        113) echo "󰖙" ;;  # Clear/Sunny
        116) echo "󰖕" ;;  # Partly cloudy
        119|122) echo "󰖐" ;;  # Cloudy/Overcast
        143|248|260) echo "󰖑" ;;  # Mist/Fog
        176|179|182|185|263|266) echo "󰖗" ;;  # Patchy/light precipitation
        200|386|389) echo "󰖓" ;;  # Thunderstorm
        227|230) echo "󰼶" ;;  # Blowing snow/Blizzard
        281|284|293|296|299|302|311|314|353|356) echo "󰖖" ;;  # Rain/Drizzle
        305|308|359) echo "󰖞" ;;  # Heavy rain
        317|320|362|365) echo "󰙿" ;;  # Sleet
        323|326|329|332|368) echo "󰖘" ;;  # Light/moderate snow
        335|338|371|392|395) echo "󰼴" ;;  # Heavy snow
        350|374|377) echo "󰖒" ;;  # Ice pellets/hail
        *) echo "󰖐" ;;  # Default: cloudy
    esac
}

# Read from cache if available and recent
if [[ -f "$CACHE_FILE" ]]; then
    CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
    if [[ $CACHE_AGE -lt 900 ]]; then  # 15 minutes
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Fetch fresh data using JSON format
WEATHER_JSON=$(curl -s --connect-timeout 5 "wttr.in/?format=j1" 2>/dev/null)

if [[ -z "$WEATHER_JSON" ]]; then
    exit 0
fi

# Extract weather code and temperature using jq
WEATHER_CODE=$(echo "$WEATHER_JSON" | jq -r '.current_condition[0].weatherCode // empty' 2>/dev/null)
TEMP=$(echo "$WEATHER_JSON" | jq -r '.current_condition[0].temp_C // empty' 2>/dev/null)

if [[ -n "$WEATHER_CODE" && -n "$TEMP" ]]; then
    ICON=$(get_weather_icon "$WEATHER_CODE")
    OUTPUT="${ICON} ${TEMP}°C"
    echo "$OUTPUT" > "$CACHE_FILE"
    echo "$OUTPUT"
else
    exit 0
fi
