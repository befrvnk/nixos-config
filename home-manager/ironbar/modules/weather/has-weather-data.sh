#!/usr/bin/env bash
# Check if weather data can be fetched
# Returns 0 (success) if data available, 1 (failure) if not
# Used by show_if to hide module when offline or no data

CACHE_FILE="$HOME/.cache/weather-status"

# Check if cache exists and is recent (less than 15 minutes old)
if [[ -f "$CACHE_FILE" ]]; then
    CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
    if [[ $CACHE_AGE -lt 900 ]]; then
        exit 0  # Cache is fresh, data available
    fi
fi

# Try to fetch weather data using JSON format
WEATHER_JSON=$(curl -s --connect-timeout 5 "wttr.in/?format=j1" 2>/dev/null)

# Check if we got valid JSON with weather data
if [[ -n "$WEATHER_JSON" ]]; then
    WEATHER_CODE=$(echo "$WEATHER_JSON" | jq -r '.current_condition[0].weatherCode // empty' 2>/dev/null)
    if [[ -n "$WEATHER_CODE" ]]; then
        exit 0  # Data available
    fi
fi

exit 1  # No data
