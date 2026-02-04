#!/usr/bin/env bash
# Fetch current weather from Open Meteo DWD ICON API
# Format: Nerd Font icon + temperature (e.g., "󰖙 22°C")
# Uses monochrome icons to match other bar modules
# Update interval: 10 minutes (600000ms)

CACHE_FILE="$HOME/.cache/weather-status"
LAT="48.1521"
LON="11.6584"

# Map WMO weather codes to Nerd Font weather icons
get_weather_icon() {
    local code="$1"
    case "$code" in
        0) echo "󰖙" ;;  # Clear sky
        1|2) echo "󰖕" ;;  # Partly cloudy
        3) echo "󰖐" ;;  # Overcast
        45|48) echo "󰖑" ;;  # Fog
        51|53|55|56|57) echo "󰖗" ;;  # Drizzle
        61|63|80|81) echo "󰖖" ;;  # Rain
        65|82) echo "󰖞" ;;  # Heavy rain
        66|67) echo "󰙿" ;;  # Freezing rain
        71|73|85) echo "󰖘" ;;  # Snow
        75|77|86) echo "󰼴" ;;  # Heavy snow
        95) echo "󰖓" ;;  # Thunderstorm
        96|99) echo "󰖒" ;;  # Thunderstorm with hail
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

# Fetch fresh data from Open Meteo DWD ICON API
WEATHER_JSON=$(curl -s --connect-timeout 5 "https://api.open-meteo.com/v1/dwd-icon?latitude=${LAT}&longitude=${LON}&current=temperature_2m,weather_code&timezone=auto" 2>/dev/null)

if [[ -z "$WEATHER_JSON" ]]; then
    exit 0
fi

# Extract weather code and temperature using jq
WEATHER_CODE=$(echo "$WEATHER_JSON" | jq -r '.current.weather_code // empty' 2>/dev/null)
TEMP=$(echo "$WEATHER_JSON" | jq -r '.current.temperature_2m // empty' 2>/dev/null)
# Round temperature to integer
TEMP=$(printf "%.0f" "$TEMP" 2>/dev/null)

if [[ -n "$WEATHER_CODE" && -n "$TEMP" ]]; then
    ICON=$(get_weather_icon "$WEATHER_CODE")
    OUTPUT="${ICON} ${TEMP}°C"
    echo "$OUTPUT" > "$CACHE_FILE"
    echo "$OUTPUT"
else
    exit 0
fi
