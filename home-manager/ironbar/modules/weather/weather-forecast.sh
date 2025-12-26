#!/usr/bin/env bash
# Fetch detailed weather from wttr.in JSON API
# Shows: current conditions + 3-day forecast

WEATHER_JSON=$(curl -s --connect-timeout 10 "wttr.in/?format=j1" 2>/dev/null)

if [[ -z "$WEATHER_JSON" ]]; then
    echo "Unable to fetch weather data"
    exit 0
fi

# Parse with jq - extract current conditions and forecast
# Current: temp, feels like, humidity, wind, description
# Forecast: date, high, low, description for each day

# Extract and format using jq
jq -r '
  # Current conditions
  "Current Conditions\n" +
  "─────────────────\n" +
  "Temperature: " + .current_condition[0].temp_C + "°C\n" +
  "Feels like: " + .current_condition[0].FeelsLikeC + "°C\n" +
  "Humidity: " + .current_condition[0].humidity + "%\n" +
  "Wind: " + .current_condition[0].windspeedKmph + " km/h " + .current_condition[0].winddir16Point + "\n" +
  .current_condition[0].weatherDesc[0].value + "\n" +
  "\n3-Day Forecast\n" +
  "─────────────────\n" +
  (.weather[:3] | to_entries | map(
    (if .key == 0 then "Today" elif .key == 1 then "Tomorrow" else .value.date end) +
    ": " + .value.mintempC + "°/" + .value.maxtempC + "°C " +
    .value.hourly[4].weatherDesc[0].value
  ) | join("\n"))
' <<< "$WEATHER_JSON" 2>/dev/null || echo "Error parsing weather data"
