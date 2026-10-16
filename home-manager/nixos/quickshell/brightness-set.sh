#!/usr/bin/env bash
# Set display brightness to an absolute 0-100 via brightnessctl (internal).
# Usage: brightness-set.sh <0-100>
set -euo pipefail

VAL=$((10#${1:-50}))
if (( VAL < 0 )); then VAL=0; fi
if (( VAL > 100 )); then VAL=100; fi

brightnessctl -d amdgpu_bl1 set "$VAL"% >/dev/null 2>&1 \
  || brightnessctl set "$VAL"% >/dev/null 2>&1 || true

# Show OSD
swayosd-client --brightness "$VAL"