#!/usr/bin/env bash
# Get current power profile from sysfs
# tuned sets platform_profile, so reading from sysfs is reliable

cat /sys/firmware/acpi/platform_profile
