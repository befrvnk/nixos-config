#!/usr/bin/env bash
# Display current CPU governor for Ironbar custom module

# Read current governor from sysfs
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)

# Display with icon based on governor
case "$GOVERNOR" in
    "schedutil")
        echo "󰓅 Performance"
        ;;
    "powersave")
        echo "󰾅 Battery"
        ;;
    *)
        echo "󰻠 $GOVERNOR"
        ;;
esac
