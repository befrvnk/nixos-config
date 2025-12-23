#!/usr/bin/env bash
PROFILE="${1:-balanced}"
echo "$PROFILE" | sudo tee /sys/firmware/acpi/platform_profile > /dev/null
