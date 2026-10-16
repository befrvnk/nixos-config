#!/usr/bin/env bash
# List Bluetooth devices as JSON: {name, mac, connected, paired}.
set -euo pipefail

bluetoothctl --timeout 5 devices 2>/dev/null | while read -r _ mac name; do
  [[ -n "$name" ]] || continue
  connected=false
  if bluetoothctl --timeout 5 info "$mac" 2>/dev/null | grep -q "^	Connected: yes"; then
    connected=true
  fi
  printf '{"name":"%s","mac":"%s","connected":%s}\n' "$name" "$mac" "$connected"
done