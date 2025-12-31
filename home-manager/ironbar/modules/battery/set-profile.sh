#!/usr/bin/env bash
# Power profile switcher using direct sysfs
# PPD's boost control is broken on kernel 6.17 + amd_pstate EPP mode,
# so we bypass it and write directly to platform_profile

PROFILE="${1:-balanced}"

# Validate and write directly to platform_profile
case "$PROFILE" in
    "low-power"|"balanced"|"performance")
        echo "$PROFILE" > /sys/firmware/acpi/platform_profile
        ;;
    *)
        echo "Unknown profile: $PROFILE"
        exit 1
        ;;
esac
