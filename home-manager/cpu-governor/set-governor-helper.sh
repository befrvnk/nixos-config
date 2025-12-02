#!/usr/bin/env bash
# Helper script for setting CPU governor (run with sudo)
# Takes governor name as argument

if [[ $# -ne 1 ]]; then
    echo "Usage: set-governor-helper [governor]"
    exit 1
fi

GOVERNOR="$1"

# Write governor to all CPU cores
echo "$GOVERNOR" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
