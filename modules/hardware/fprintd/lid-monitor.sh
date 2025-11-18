#!/usr/bin/env bash

# Function to check lid state
check_lid_state() {
  # Check /proc/acpi/button/lid/LID0/state or similar
  for lid in /proc/acpi/button/lid/*/state; do
    if [ -f "$lid" ]; then
      state=$(cat "$lid" | awk '{print $2}')
      echo "$state"
      return
    fi
  done
  echo "open"  # Default to open if we can't detect
}

previous_state=""

while true; do
  current_state=$(check_lid_state)

  if [ "$current_state" != "$previous_state" ]; then
    echo "Lid state changed: $current_state"

    if [ "$current_state" = "closed" ]; then
      echo "Lid closed - stopping fprintd"
      systemctl stop fprintd.service || true
    elif [ "$current_state" = "open" ]; then
      echo "Lid opened - starting fprintd"
      systemctl start fprintd.service || true
    fi

    previous_state="$current_state"
  fi

  sleep 2
done
