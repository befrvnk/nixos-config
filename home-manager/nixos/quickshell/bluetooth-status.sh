#!/usr/bin/env bash
# Show Bluetooth status for the bar: icon + count of connected devices.
set -euo pipefail

if ! bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
  echo "󰂯 Off"
  exit 0
fi

COUNT=$(bluetoothctl devices Connected 2>/dev/null | wc -l)
if [[ "$COUNT" -gt 0 ]]; then
  echo "󰂯 $COUNT"
else
  echo "󰂯"
fi