#!/usr/bin/env bash
# Refresh the existing awww wallpaper from Noctalia's resolved mode after hotplug.
set -euo pipefail

udevadm monitor --udev --subsystem-match=drm | while IFS= read -r line; do
  if [[ "$line" == *change* ]]; then
    sleep 2
    "$1" --refresh
  fi
done
