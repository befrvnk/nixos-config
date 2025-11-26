#!/usr/bin/env bash
# Script to prevent auto-suspend while any media is playing
# Works with YouTube, Spotify, VLC, and any MPRIS-compatible player
# Does NOT prevent manual suspend (lid close)

inhibitor_pid=""

cleanup() {
  if [ -n "$inhibitor_pid" ]; then
    # Kill the systemd-inhibit process and its child (sleep infinity)
    kill "$inhibitor_pid" 2>/dev/null
    wait "$inhibitor_pid" 2>/dev/null
    inhibitor_pid=""
  fi
}

trap cleanup EXIT

while true; do
  # Check if any media player is currently playing
  status=$(playerctl status 2>/dev/null || echo "Stopped")

  if [ "$status" = "Playing" ]; then
    # Music is playing - acquire inhibitor lock if we don't have one
    if [ -z "$inhibitor_pid" ] || ! kill -0 "$inhibitor_pid" 2>/dev/null; then
      # Start systemd-inhibit in the background and save its PID
      systemd-inhibit \
        --what=idle \
        --who="Audio Playback" \
        --why="Music is playing" \
        --mode=block \
        sleep infinity &
      inhibitor_pid=$!
    fi
  else
    # Music stopped - release inhibitor lock
    cleanup
  fi

  sleep 5
done
