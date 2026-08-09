#!/usr/bin/env bash
# Ironbar bar label: OpenRouter monthly cost · today's cost, both from
# OpenRouter's own API (today = month minus completed days this month).
# Matches the browser and does NOT use pi's local session accounting.
# Polled every 5 minutes (300000ms) via config.json.
set -euo pipefail

ICON="󰮝" # nf-md-chart_line
DIR="$(dirname "$0")"

ACCT="$("$DIR/account.sh" 2>/dev/null)" || ACCT=''
month_usage="$(printf '%s' "$ACCT" | jq -r '.month_usage // empty')"
today_usage="$(printf '%s' "$ACCT" | jq -r '.today_usage // empty')"

if [[ -z "$month_usage" ]]; then
    # No account data (offline / key missing) - degrade gracefully.
    printf '%s ?\n' "$ICON"
    exit 0
fi

printf '%s $%.2f/m · $%.2f/d\n' "$ICON" "$month_usage" "${today_usage:-0}"