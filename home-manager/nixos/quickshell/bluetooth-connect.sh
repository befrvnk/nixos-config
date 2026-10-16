#!/usr/bin/env bash
# Connect to a Bluetooth device. Usage: bluetooth-connect.sh <mac> [1 for connect, 0 for disconnect]
set -euo pipefail
MAC="$1"
ACTION="${2:-1}"

if [[ "$ACTION" == "1" ]]; then
  bluetoothctl --timeout 10 connect "$MAC" >/dev/null 2>&1 || true
else
  bluetoothctl --timeout 5 disconnect "$MAC" >/dev/null 2>&1 || true
fi