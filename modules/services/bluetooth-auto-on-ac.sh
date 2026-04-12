#!/usr/bin/env bash

set -euo pipefail

acDevice="$(upower -e | grep -m1 '/line_power_' || true)"
if [[ -z "$acDevice" ]]; then
  echo "No AC adapter device found in UPower" >&2
  exit 1
fi

power_on_bluetooth() {
  for _ in 1 2 3 4 5; do
    if bluetoothctl --timeout 5 power on >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 0
}

current_online="$(upower -i "$acDevice" | grep -oP 'online:\s+\K(yes|no)' || echo no)"
if [[ "$current_online" == "yes" ]]; then
  power_on_bluetooth
fi

monitoring_device=false
last_online="$current_online"

upower --monitor-detail 2>/dev/null | while IFS= read -r line; do
  if [[ "$line" =~ device\ changed:[[:space:]]+(.+) ]]; then
    current_device="${BASH_REMATCH[1]}"
    monitoring_device=false
    if [[ "$current_device" == "$acDevice" ]]; then
      monitoring_device=true
    fi
    continue
  fi

  if [[ "$monitoring_device" == false ]]; then
    continue
  fi

  if [[ "$line" =~ online:[[:space:]]+(yes|no) ]]; then
    current_online="${BASH_REMATCH[1]}"
    if [[ "$current_online" == "yes" && "$last_online" != "yes" ]]; then
      power_on_bluetooth
    fi
    last_online="$current_online"
  fi
done
