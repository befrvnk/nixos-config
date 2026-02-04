#!/usr/bin/env bash
# Prevent idle/suspend while audio is actually playing
# Uses the same detection logic as ironbar: count [active] streams > 2
# (baseline of 2 accounts for the Framework speaker filter-chain)

inhibitor_pid=""

cleanup() {
  if [ -n "$inhibitor_pid" ]; then
    kill "$inhibitor_pid" 2>/dev/null
    wait "$inhibitor_pid" 2>/dev/null
    inhibitor_pid=""
  fi
}

trap cleanup EXIT

# Check if audio is actually playing via wpctl
# >2 active channels means actual audio (baseline is 2 from filter-chain)
is_audio_playing() {
  local status
  status=$(wpctl status 2>/dev/null)
  # If [paused] exists, media is paused
  if echo "$status" | grep -q '\[paused\]'; then
    return 1
  fi
  # >2 active channels means actual audio playing
  [ "$(echo "$status" | grep -c '\[active\]')" -gt 2 ]
}

while true; do
  if is_audio_playing; then
    # Audio is playing - acquire inhibitor lock if we don't have one
    if [ -z "$inhibitor_pid" ] || ! kill -0 "$inhibitor_pid" 2>/dev/null; then
      # Inhibit both idle and sleep while audio is playing
      systemd-inhibit \
        --what=idle:sleep \
        --who="Audio Playback" \
        --why="Audio is playing" \
        --mode=block \
        sleep infinity &
      inhibitor_pid=$!
    fi
  else
    # Audio stopped - release inhibitor lock
    cleanup
  fi

  sleep 10
done
