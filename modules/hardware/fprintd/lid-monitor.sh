#!/usr/bin/env bash

# Flag file to indicate lid is closed - fprintd.service has a ConditionPathExists
# that prevents it from starting when this file exists
LID_CLOSED_FLAG="/run/fprintd-lid-closed"

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
      echo "Lid closed - creating flag file and stopping fprintd"
      touch "$LID_CLOSED_FLAG"
      systemctl stop fprintd.service 2>/dev/null || true
    elif [ "$current_state" = "open" ]; then
      echo "Lid opened - removing flag file"
      rm -f "$LID_CLOSED_FLAG"
      # fprintd will start on-demand via D-Bus when needed
    fi

    previous_state="$current_state"
  fi

  sleep 2
done
