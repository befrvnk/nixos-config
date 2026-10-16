#!/usr/bin/env bash
# Toggle WiFi radio via nmcli (used by the wifi manager module).
set -euo pipefail

if nmcli radio wifi | grep -q '^enabled'; then
  nmcli radio wifi off
else
  nmcli radio wifi on
fi