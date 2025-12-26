#!/usr/bin/env bash
# Unified power profile switcher
# Sets platform profile, EPP, and CPU boost together for coherent power management

PROFILE="${1:-balanced}"

# Map profile to EPP and boost settings
case "$PROFILE" in
    "low-power")
        EPP="power"
        BOOST=0
        ;;
    "balanced")
        EPP="balance_performance"
        BOOST=1
        ;;
    "performance")
        EPP="performance"
        BOOST=1
        ;;
    *)
        echo "Unknown profile: $PROFILE"
        exit 1
        ;;
esac

# Set platform profile (fans, thermals, power limits)
echo "$PROFILE" | sudo tee /sys/firmware/acpi/platform_profile > /dev/null

# Set EPP for all CPUs (frequency scaling hints)
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo "$EPP" | sudo tee "$cpu" > /dev/null 2>&1
done

# Set CPU boost
echo "$BOOST" | sudo tee /sys/devices/system/cpu/cpufreq/boost > /dev/null 2>&1
