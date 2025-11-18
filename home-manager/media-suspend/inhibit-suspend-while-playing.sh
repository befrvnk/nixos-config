#!/usr/bin/env bash
# Script to prevent auto-suspend while any media is playing
# Works with YouTube, Spotify, VLC, and any MPRIS-compatible player
# Does NOT prevent manual suspend (lid close)

inhibitor_fd=""

cleanup() {
  if [ -n "$inhibitor_fd" ]; then
    exec {inhibitor_fd}>&-
    inhibitor_fd=""
  fi
}

trap cleanup EXIT

while true; do
  # Check if any media player is currently playing
  status=$(playerctl status 2>/dev/null || echo "Stopped")

  if [ "$status" = "Playing" ]; then
    # Music is playing - acquire inhibitor lock if we don't have one
    if [ -z "$inhibitor_fd" ]; then
      exec {inhibitor_fd}<> <(systemd-inhibit \
        --what=idle \
        --who="Audio Playback" \
        --why="Music is playing" \
        --mode=block \
        sleep infinity 2>&1)
    fi
  else
    # Music stopped - release inhibitor lock
    cleanup
  fi

  sleep 5
done
