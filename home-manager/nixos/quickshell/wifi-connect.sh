#!/usr/bin/env bash
# Connect to WiFi. Usage: wifi-connect.sh <ssid> [password]
# If already connected, no-op. Uses nmcli; with a password for secured networks.
set -euo pipefail

SSID="$1"
PASS="${2:-}"

# Escape SSID for CLI (pass as separate arg; many chars are fine as one token).
if [[ -z "$PASS" ]]; then
  nmcli device wifi connect "$SSID" 2>/dev/null \
    || nmcli connection up "$SSID" 2>/dev/null \
    || exit 1
else
  nmcli device wifi connect "$SSID" password "$PASS" 2>/dev/null \
    || nmcli connection up "$SSID" 2>/dev/null \
    || exit 1
fi