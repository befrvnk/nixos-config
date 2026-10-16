#!/usr/bin/env bash
# Set volume to an absolute 0-100 via wpctl, then write the cache that
# volume-status reads. Usage: volume-set.sh <0-100>   (or "mute").
set -euo pipefail

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/volume-status"
mkdir -p "$(dirname "$CACHE_FILE")"

refresh_cache() {
  local sink_id volume_info volume icon
  sink_id=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'id \K\d+' | head -1)
  [[ -n "$sink_id" ]] || { echo "󰖁 N/A" > "$CACHE_FILE"; return; }

  volume_info=$(wpctl get-volume "$sink_id" 2>/dev/null)
  volume=$(echo "$volume_info" | awk '{print int($2 * 100)}')
  if echo "$volume_info" | grep -q MUTED; then icon="󰖁"
  elif (( volume == 0 )); then icon="󰖁"
  elif (( volume < 33 )); then icon="󰕿"
  elif (( volume < 66 )); then icon="󰖀"
  else icon="󰕾"; fi
  printf '%s %d%%\n' "$icon" "$volume" > "$CACHE_FILE"
}

case "${1:-}" in
  mute)
    swayosd-client --output-volume mute-toggle
    refresh_cache
    exit 0
    ;;
esac

VAL=$((10#${1:-50}))
if (( VAL < 0 )); then VAL=0; fi
if (( VAL > 100 )); then VAL=100; fi

PERMIL=$((VAL * 1000 / 100))
if (( VAL == 0 )); then
  wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.0
else
  wpctl set-volume @DEFAULT_AUDIO_SINK@ "0.$PERMIL"
fi

refresh_cache

# OSD (best-effort)
swayosd-client --output-volume "$VAL" 2>/dev/null || true