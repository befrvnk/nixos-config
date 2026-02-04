#!/usr/bin/env bash
# Fetch detailed weather from Open Meteo DWD ICON API
# Shows: current conditions + 3-day forecast

LAT="48.1521"
LON="11.6584"

# Convert wind direction degrees to 16-point compass
degrees_to_compass() {
    local deg=$1
    local dirs=("N" "NNE" "NE" "ENE" "E" "ESE" "SE" "SSE" "S" "SSW" "SW" "WSW" "W" "WNW" "NW" "NNW")
    local index=$(( (deg + 11) / 22 % 16 ))
    echo "${dirs[$index]}"
}

# Convert WMO weather code to description
wmo_to_description() {
    local code=$1
    case "$code" in
        0) echo "Clear sky" ;;
        1) echo "Mainly clear" ;;
        2) echo "Partly cloudy" ;;
        3) echo "Overcast" ;;
        45) echo "Fog" ;;
        48) echo "Depositing rime fog" ;;
        51) echo "Light drizzle" ;;
        53) echo "Moderate drizzle" ;;
        55) echo "Dense drizzle" ;;
        56|57) echo "Freezing drizzle" ;;
        61) echo "Slight rain" ;;
        63) echo "Moderate rain" ;;
        65) echo "Heavy rain" ;;
        66|67) echo "Freezing rain" ;;
        71) echo "Slight snow" ;;
        73) echo "Moderate snow" ;;
        75) echo "Heavy snow" ;;
        77) echo "Snow grains" ;;
        80) echo "Slight rain showers" ;;
        81) echo "Moderate rain showers" ;;
        82) echo "Violent rain showers" ;;
        85) echo "Slight snow showers" ;;
        86) echo "Heavy snow showers" ;;
        95) echo "Thunderstorm" ;;
        96|99) echo "Thunderstorm with hail" ;;
        *) echo "Unknown" ;;
    esac
}

WEATHER_JSON=$(curl -s --connect-timeout 10 "https://api.open-meteo.com/v1/dwd-icon?latitude=${LAT}&longitude=${LON}&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=3" 2>/dev/null)

if [[ -z "$WEATHER_JSON" ]]; then
    echo "Unable to fetch weather data"
    exit 0
fi

# Extract current conditions
TEMP=$(echo "$WEATHER_JSON" | jq -r '.current.temperature_2m // empty')
FEELS_LIKE=$(echo "$WEATHER_JSON" | jq -r '.current.apparent_temperature // empty')
HUMIDITY=$(echo "$WEATHER_JSON" | jq -r '.current.relative_humidity_2m // empty')
WIND_SPEED=$(echo "$WEATHER_JSON" | jq -r '.current.wind_speed_10m // empty')
WIND_DIR=$(echo "$WEATHER_JSON" | jq -r '.current.wind_direction_10m // empty')
WEATHER_CODE=$(echo "$WEATHER_JSON" | jq -r '.current.weather_code // empty')

if [[ -z "$TEMP" ]]; then
    echo "Error parsing weather data"
    exit 0
fi

# Convert wind direction and get weather description
WIND_COMPASS=$(degrees_to_compass "${WIND_DIR%.*}")
DESCRIPTION=$(wmo_to_description "$WEATHER_CODE")

# Print current conditions
printf "Current Conditions\n"
printf "─────────────────\n"
printf "Temperature: %.0f°C\n" "$TEMP"
printf "Feels like: %.0f°C\n" "$FEELS_LIKE"
printf "Humidity: %.0f%%\n" "$HUMIDITY"
printf "Wind: %.0f km/h %s\n" "$WIND_SPEED" "$WIND_COMPASS"
printf "%s\n" "$DESCRIPTION"
printf "\n3-Day Forecast\n"
printf "─────────────────\n"

# Extract and print forecast
for i in 0 1 2; do
    DATE=$(echo "$WEATHER_JSON" | jq -r ".daily.time[$i] // empty")
    MIN=$(echo "$WEATHER_JSON" | jq -r ".daily.temperature_2m_min[$i] // empty")
    MAX=$(echo "$WEATHER_JSON" | jq -r ".daily.temperature_2m_max[$i] // empty")
    CODE=$(echo "$WEATHER_JSON" | jq -r ".daily.weather_code[$i] // empty")
    DESC=$(wmo_to_description "$CODE")

    if [[ $i -eq 0 ]]; then
        DAY="Today"
    elif [[ $i -eq 1 ]]; then
        DAY="Tomorrow"
    else
        DAY="$DATE"
    fi

    printf "%s: %.0f°/%.0f°C %s\n" "$DAY" "$MIN" "$MAX" "$DESC"
done
