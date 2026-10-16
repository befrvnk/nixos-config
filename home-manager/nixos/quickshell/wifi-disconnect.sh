#!/usr/bin/env bash
# Disconnect from the current WiFi network via nmcli.
set -euo pipefail

ACTIVE_CONNECTION="$(nmcli -t -f TYPE,NAME connection show --active 2>/dev/null | awk -F: '$1=="802-11-wireless"{print $2}' | head -1)"
if [[ -n "$ACTIVE_CONNECTION" ]]; then
  nmcli connection down "$ACTIVE_CONNECTION" 2>/dev/null || true
fi