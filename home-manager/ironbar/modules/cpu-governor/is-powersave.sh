#!/usr/bin/env bash
# Returns exit code 0 if CPU governor is powersave (show module)
# Returns exit code 1 otherwise (hide module)

GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)

if [ "$GOVERNOR" = "powersave" ]; then
    exit 0
else
    exit 1
fi
