#!/usr/bin/env bash

set -euo pipefail

acOnlinePath=""
for supply in /sys/class/power_supply/*; do
  if [[ "$(cat "$supply/type")" == "Mains" ]]; then
    acOnlinePath="$supply/online"
    break
  fi
done
if [[ -z "$acOnlinePath" ]]; then
  echo "No AC adapter found in sysfs" >&2
  exit 1
fi

set_profile() {
  busctl --system set-property net.hadess.PowerProfiles /net/hadess/PowerProfiles \
    net.hadess.PowerProfiles ActiveProfile s "$1"
}

last_online="$(cat "$acOnlinePath")"

while sleep 2; do
  current_online="$(cat "$acOnlinePath")"
  if [[ "$current_online" != "$last_online" ]]; then
    last_online="$current_online"
    if [[ "$current_online" == "1" ]]; then
      set_profile performance
    else
      set_profile balanced
    fi
  fi
done
