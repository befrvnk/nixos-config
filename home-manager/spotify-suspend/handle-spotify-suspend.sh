#!/usr/bin/env bash
# Monitor suspend/resume events and pause/resume Spotify
# This prevents audio device disconnection crashes during suspend

busctl monitor --user --match="interface=org.freedesktop.login1.Manager,member=PrepareForSleep" | \
while read -r line; do
  if echo "$line" | grep -q "boolean true"; then
    # System is about to suspend
    status=$(playerctl -p spotify status 2>/dev/null || echo "Stopped")
    if [ "$status" = "Playing" ]; then
      playerctl -p spotify pause 2>/dev/null || true
      echo "true" > /tmp/spotify-was-playing-$USER
    else
      rm -f /tmp/spotify-was-playing-$USER
    fi
  elif echo "$line" | grep -q "boolean false"; then
    # System resumed - wait for audio devices and resume if needed
    sleep 2
    if [ -f /tmp/spotify-was-playing-$USER ]; then
      playerctl -p spotify play 2>/dev/null || true
      rm -f /tmp/spotify-was-playing-$USER
    fi
  fi
done
