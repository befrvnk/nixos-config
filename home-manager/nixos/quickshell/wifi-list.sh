#!/usr/bin/env bash
# List available WiFi networks as a JSON array of
# {ssid, signal, secured, active, inUse}. Uses nmcli.
set -euo pipefail

# Current network SSID
ACTIVE="$(nmcli -t -f ACTIVE,SSID device wifi list 2>/dev/null | awk -F: '$1=="yes"{print $2}')"

nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list 2>/dev/null | while IFS=: read -r inuse signal security ssid; do
  # skip header / empty ssid
  [[ -n "$ssid" ]] || continue
  # preserve SSIDs with special chars via %XX style is unreliable; use only name
  secured="false"
  [[ "$security" != "" && "$security" != "--" ]] && secured=true
  active=false
  [[ "$inuse" == "*" || "$ssid" == "$ACTIVE" ]] && active=true
  printf '{"name":"%s","secured":%s,"active":%s}\n' "$ssid" "$secured" "$active"
done