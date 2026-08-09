#!/usr/bin/env bash
# Ironbar popup content for the OpenRouter module.
# All figures come from OpenRouter's own API (credits + activity) - the same
# data the activity page shows. No pi session cost accounting involved.
#
#   today        -> month (credits) minus completed days this month (activity)
#   recent days  -> /api/v1/activity (last completed UTC days; lags today)
#   per model    -> /api/v1/activity (30 days)
set -euo pipefail

ICON="󰮝" # nf-md-chart_line
DIR="$(dirname "$0")"

ACCT="$("$DIR/account.sh" 2>/dev/null)" || ACCT=''
balance="$(printf '%s' "$ACCT" | jq -r '.balance // empty')"
month_usage="$(printf '%s' "$ACCT" | jq -r '.month_usage // empty')"
today_usage="$(printf '%s' "$ACCT" | jq -r '.today_usage // empty')"
has_activity="$(printf '%s' "$ACCT" | jq -r '(.activity | length) // 0')"

printf '%s OpenRouter (OpenRouter data)\n' "$ICON"
printf '────────────────────────────────\n'
printf '%-18s $%.2f\n' "Balance" "${balance:-0}"
printf '%-18s $%.2f\n' "Used (month)" "${month_usage:-0}"
printf '%-18s $%.2f\n' "Today (live)" "${today_usage:-0}"

if [[ "$has_activity" == "0" ]]; then
    printf '────────────────────────────────\n'
    printf '%s\n' "History: unavailable (no management key)"
    printf 'See README: ~/.config/openrouter/management.key\n'
    exit 0
fi

# --- Recent completed days ----------------------------------------------
printf '────────────────────────────────\n'
printf '%s\n' "Recent days (completed UTC)"
printf '  %-10s %5s  %s\n' "date" "reqs" "cost"
while IFS=$'\t' read -r day req usage; do
    [[ -n "$day" ]] || continue
    printf '  %-10s %5d  $%.2f\n' "$day" "$req" "$usage"
done < <(
    printf '%s' "$ACCT" | jq -r '
        .activity | group_by(.date) | map({date: .[0].date,
                                           req: (map(.requests // 0) | add),
                                           usage: (map(.usage // 0) | add)})
        | sort_by(.date) | .[-7:][] | [.date, .req, .usage] | @tsv'
)

# --- Per-model totals (30 days) -----------------------------------------
printf '────────────────────────────────\n'
printf '%s\n' "Per model (30 days)"
printf '  %-30s %5s  %s\n' "model" "reqs" "cost"
while IFS=$'\t' read -r model req usage; do
    [[ -n "$model" ]] || continue
    printf '  %-30s %5d  $%.2f\n' "$model" "$req" "$usage"
done < <(
    printf '%s' "$ACCT" | jq -r '
        .activity | group_by(.model) | map({model: .[0].model,
                                            req: (map(.requests // 0) | add),
                                            usage: (map(.usage // 0) | add)})
        | sort_by(.usage) | reverse | .[] | [.model, .req, .usage] | @tsv'
)