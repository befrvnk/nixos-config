#!/usr/bin/env bash
# Shared helpers for the exa-search skill scripts.

EXA_MCP_URL="${EXA_MCP_URL:-https://mcp.exa.ai/mcp}"
EXA_CURL_RETRIES="${EXA_CURL_RETRIES:-2}"
EXA_CONNECT_TIMEOUT="${EXA_CONNECT_TIMEOUT:-10}"

exa_require_tools() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "Missing required command: curl" >&2
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "Missing required command: jq" >&2
    return 1
  fi
}

exa_extract_event_json() {
  local raw="$1"
  local parsed

  if ! parsed=$(
    while IFS= read -r event_line || [[ -n "$event_line" ]]; do
      event_line=${event_line%$'\r'}
      [[ "$event_line" == data:\ * ]] || continue
      json_line="${event_line#data: }"
      if printf '%s' "$json_line" | jq -e . >/dev/null 2>&1; then
        printf '%s\n' "$json_line"
      fi
    done <<< "$raw" | jq -sc '
      (if length == 0 then error("no-valid-events") else . end)
      | (map(select(.error? != null)) | last) as $error
      | (map(select(.result.content?[0]? != null)) | last) as $result
      | if $error != null then
          {status:"error", event:$error}
        elif $result != null then
          {status:"ok", event:$result}
        else
          {status:"empty"}
        end
    '
  ); then
    echo "Failed to parse or interpret Exa MCP response events" >&2
    return 1
  fi

  printf '%s' "$parsed"
}

exa_call_mcp() {
  local tool_name="$1"
  local arguments_json="$2"
  local max_time="${3:-30}"
  local payload response marker http_code raw parsed status error_message error_code

  exa_require_tools || return 1

  payload=$(jq -nc \
    --arg toolName "$tool_name" \
    --argjson arguments "$arguments_json" \
    '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:$toolName,arguments:$arguments}}')

  marker=$'\n__EXA_HTTP_STATUS__:'

  if ! response=$(curl -sS \
    --retry "$EXA_CURL_RETRIES" \
    --retry-delay 1 \
    --connect-timeout "$EXA_CONNECT_TIMEOUT" \
    --max-time "$max_time" \
    -H 'accept: application/json, text/event-stream' \
    -H 'content-type: application/json' \
    --data "$payload" \
    -w "${marker}%{http_code}" \
    "$EXA_MCP_URL"); then
    echo "Failed to call Exa MCP endpoint" >&2
    [[ -n "$response" ]] && printf '%s\n' "$response" >&2
    return 1
  fi

  if [[ "$response" != *"$marker"* ]]; then
    echo "Failed to call Exa MCP endpoint: missing HTTP status marker" >&2
    [[ -n "$response" ]] && printf '%s\n' "$response" >&2
    return 1
  fi

  http_code="${response##*"$marker"}"
  raw="${response%"$marker"*}"

  if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
    echo "Failed to call Exa MCP endpoint: unexpected HTTP status '$http_code'" >&2
    [[ -n "$raw" ]] && printf '%s\n' "$raw" >&2
    return 1
  fi

  if (( http_code < 200 || http_code >= 300 )); then
    echo "Exa MCP request failed with HTTP $http_code" >&2
    [[ -n "$raw" ]] && printf '%s\n' "$raw" >&2
    return 1
  fi

  parsed=$(exa_extract_event_json "$raw") || return 1
  status=$(printf '%s' "$parsed" | jq -r '.status')

  case "$status" in
    ok)
      printf '%s' "$parsed" | jq -c '.event'
      ;;
    error)
      error_message=$(printf '%s' "$parsed" | jq -r '.event.error.message // "Unknown Exa MCP error"')
      error_code=$(printf '%s' "$parsed" | jq -r '.event.error.code // empty')
      if [[ -n "$error_code" ]]; then
        echo "Exa MCP error ($error_code): $error_message" >&2
      else
        echo "Exa MCP error: $error_message" >&2
      fi
      return 1
      ;;
    empty)
      echo "Exa MCP response did not include a usable result" >&2
      return 1
      ;;
    *)
      echo "Unexpected Exa MCP parser status: $status" >&2
      return 1
      ;;
  esac
}
