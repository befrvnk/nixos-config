#!/usr/bin/env bash
# OpenRouter account usage, sourced entirely from OpenRouter's own API.
#
#  * monthly usage + balance:   /api/v1/credits (real-time, any key)
#  * today's usage:             month-usage MINUS the sum of /api/v1/activity
#                               completed days in the current month (= today).
#                               (/api/v1/activity omits the in-progress day, so
#                               this reproduces the browser's live "today".)
#  * daily/per-model history:   /api/v1/activity (last completed UTC days,
#                               requires a management key)
#
# This does NOT rely on pi's local session cost accounting.
#
# Usage:
#   account.sh -> print cached/refreshed JSON
#   account.sh --refresh -> force a refresh regardless of cache age
#
# JSON output:
#   { "balance": <usd>, "month_usage": <usd-this-month>, "today_usage": <usd-today>,
#     "day": <UTC YYYY-MM-DD>, "day_start_usage": <usd - fallback baseline>,
#     "ts": <epoch>, "activity": [ {date, model, requests, usage, ...}, ... ] }
#
# Key resolution:
#   1) Management key from $HOME/.config/openrouter/management.key (preferred,
#      required for /activity). Stored outside the repo, mode 0600.
#   2) Fallback to pi's own key (~/.pi/agent/auth.json) for credits/month only;
#      today then uses a day-delta estimate, /activity history is unavailable.
set -euo pipefail

AUTH_FILE="${AUTH_FILE:-$HOME/.pi/agent/auth.json}"
MGMT_KEY_FILE="${MGMT_KEY_FILE:-$HOME/.config/openrouter/management.key}"
CACHE_FILE="${CACHE_FILE:-$HOME/.cache/openrouter-account.json}"
CACHE_TTL="${OPENROUTER_CACHE_TTL:-120}" # seconds; bar won't re-poll the API under this

# $1 = key -> echoes "balance|month_usage"
fetch_credits() {
    local j bal month
    j="$(curl -fsS -m 20 -H "Authorization: Bearer $1" \
        https://openrouter.ai/api/v1/credits 2>/dev/null)" || return 1
    bal="$(printf '%s' "$j" | jq -r '.data.total_credits // 0')"
    month="$(printf '%s' "$j" | jq -r '.data.total_usage // 0')"
    printf '%s|%s\n' "$bal" "$month"
}

refresh() {
    local mgmt_key key credits bal month today month_prefix act today_usage
    local cached_day day_start

    mgmt_key=""
    [[ -f "$MGMT_KEY_FILE" ]] && mgmt_key="$(tr -d '[:space:]\n' < "$MGMT_KEY_FILE")"

    key="$mgmt_key"
    [[ -z "$key" ]] && key="$(jq -r '.openrouter.access // empty' "$AUTH_FILE" 2>/dev/null || true)"
    [[ -n "$key" ]] || return 1

    credits="$(fetch_credits "$key" || echo '0|0')"
    bal="${credits%%|*}"
    month="${credits##*|}"

    today="$(date -u +%F)"
    month_prefix="$(date -u +%Y-%m)"

    # History (completed UTC days; /activity excludes the in-progress day).
    # Only available with a management key.
    act="[]"
    if [[ -n "$mgmt_key" ]]; then
        act="$(curl -fsS -m 30 -H "Authorization: Bearer $mgmt_key" \
            https://openrouter.ai/api/v1/activity 2>/dev/null \
            | jq -c '[.data[]? | {date: (.date[:10]), model, requests, usage,
                prompt_tokens: .promptTokens, completion_tokens: .completionTokens,
                reasoning_tokens: .reasoningTokens}]')" \
            || act="[]"
    fi
    [[ -n "$act" && "$(printf '%s' "$act" | jq -r 'type' 2>/dev/null || true)" == "array" ]] || act="[]"

    # ---- Today's spend, authoritative ----
    # Primary (mgmt key): month - (completed days this month). /credits month is
    # real-time; /activity sums only prior, completed days.
    if [[ "$act" != "[]" ]]; then
        today_usage="$(jq -nr --arg m "$month" --arg p "$month_prefix" --argjson a "$act" \
            '([($m | tonumber) - ([$a[] | select(.date | startswith($p)) | .usage] | add // 0), 0] | max)')"
    else
        # Fallback (no mgmt key): live delta since a day-start baseline.
        if [[ -f "$CACHE_FILE" ]] && [[ -s "$CACHE_FILE" ]]; then
            cached_day="$(jq -r '.day // ""' "$CACHE_FILE" 2>/dev/null || true)"
            day_start="$(jq -r '.day_start_usage // 0' "$CACHE_FILE" 2>/dev/null || true)"
        else
            cached_day=""
            day_start=0
        fi
        if [[ "$cached_day" != "$today" ]] \
            || [[ "$(jq -n --arg m "$month" --arg s "$day_start" '$m|tonumber < ($s|tonumber)')" == "true" ]]; then
            day_start="$month"
        fi
        today_usage="$(jq -n --arg m "$month" --arg s "$day_start" \
            '([($m | tonumber) - ($s | tonumber), 0] | max)')"
    fi

    mkdir -p "$(dirname "$CACHE_FILE")"
    jq -n --arg bal "$bal" --arg month "$month" --arg today "$today" \
        --arg dstart "${day_start:-0}" --arg tu "$today_usage" --arg ts "$(date +%s)" \
        --argjson activity "$act" \
        '{ balance: ($bal | tonumber), month_usage: ($month | tonumber),
           today_usage: ($tu | tonumber), day: $today, day_start_usage: ($dstart | tonumber),
           ts: ($ts | tonumber), activity: $activity }' > "$CACHE_FILE" || return 1
}

cache_fresh() {
    [[ -f "$CACHE_FILE" ]] || return 1
    [[ -s "$CACHE_FILE" ]] || return 1
    # Reject malformed/legacy caches (e.g. today_usage:null) so we refresh.
    [[ "$(jq -r '.today_usage | type' "$CACHE_FILE" 2>/dev/null || echo missing)" == "number" ]] || return 1
    (( $(date +%s) - $(jq -r '.ts // 0' "$CACHE_FILE" 2>/dev/null || echo 0) <= CACHE_TTL ))
}

if [[ "${1:-}" == "--refresh" ]]; then
    refresh || true
else
    cache_fresh || refresh || true
fi

cat "$CACHE_FILE" 2>/dev/null \
    || echo '{"balance":0,"month_usage":0,"today_usage":0,"day":"","ts":0,"activity":[]}'