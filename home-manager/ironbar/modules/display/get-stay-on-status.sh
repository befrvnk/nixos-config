#!/usr/bin/env bash
# Get manual stay-on status for ironbar button label
# Queries stasis for inhibit status

STATUS=$(stasis info --json 2>/dev/null)

# Check for various possible field names in stasis JSON output
if echo "$STATUS" | grep -qE '"(manually_inhibited|paused|inhibited)":\s*true'; then
    echo "󰈈 Stay On: ON"
else
    echo "󰈈 Stay On: OFF"
fi
