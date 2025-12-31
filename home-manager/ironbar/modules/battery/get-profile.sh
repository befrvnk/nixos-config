#!/usr/bin/env bash
# Get current power profile from sysfs
# PPD's state is unreliable on kernel 6.17 + amd_pstate EPP mode,
# so we read directly from platform_profile

cat /sys/firmware/acpi/platform_profile
