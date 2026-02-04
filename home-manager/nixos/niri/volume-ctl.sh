#!/usr/bin/env bash
# Event-driven volume control (calls swayosd + updates cache for ironbar)
# This eliminates dbus polling overhead - wpctl only runs when volume changes
# PATH is set by the wrapper in default.nix

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/volume-status"
mkdir -p "$(dirname "$CACHE_FILE")"

update_cache() {
  local sink_id volume_info volume icon
  sink_id=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP 'id \K\d+' | head -1)

  if [ -z "$sink_id" ]; then
    echo "󰖁 N/A" > "$CACHE_FILE"
    return
  fi

  volume_info=$(wpctl get-volume "$sink_id" 2>/dev/null)
  volume=$(echo "$volume_info" | awk '{print int($2 * 100)}')

  if echo "$volume_info" | grep -q "MUTED"; then
    icon="󰖁"
  elif [ "$volume" -eq 0 ]; then
    icon="󰖁"
  elif [ "$volume" -lt 33 ]; then
    icon="󰕿"
  elif [ "$volume" -lt 66 ]; then
    icon="󰖀"
  else
    icon="󰕾"
  fi
  echo "$icon ${volume}%" > "$CACHE_FILE"
}

case "${1:-}" in
  raise)
    swayosd-client --output-volume raise
    sleep 0.05
    update_cache
    ;;
  lower)
    swayosd-client --output-volume lower
    sleep 0.05
    update_cache
    ;;
  mute-toggle)
    swayosd-client --output-volume mute-toggle
    sleep 0.05
    update_cache
    ;;
  init)
    update_cache
    ;;
  *)
    echo "Usage: volume-ctl {raise|lower|mute-toggle|init}" >&2
    exit 1
    ;;
esac
