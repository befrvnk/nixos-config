#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./exa-mcp.sh
source "$SCRIPT_DIR/exa-mcp.sh"

usage() {
  cat <<'EOF'
Usage:
  code-search.sh "query" [--tokens N] [--json]

Examples:
  code-search.sh "React useEffect cleanup examples"
  code-search.sh "Next.js partial prerendering configuration" --tokens 8000
  code-search.sh "Python pandas dataframe filtering" --json
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

QUERY=""
TOKENS=5000
JSON_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tokens|--tokens-num)
      TOKENS="${2:-}"
      shift 2
      ;;
    --json)
      JSON_MODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$QUERY" ]]; then
        QUERY="$1"
      else
        QUERY+=" $1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "Missing query" >&2
  usage >&2
  exit 1
fi

if ! [[ "$TOKENS" =~ ^[0-9]+$ ]] || (( TOKENS < 1000 || TOKENS > 50000 )); then
  echo "Invalid --tokens: $TOKENS (expected 1000-50000)" >&2
  exit 1
fi

arguments_json=$(jq -nc \
  --arg query "$QUERY" \
  --argjson tokensNum "$TOKENS" \
  '{query:$query,tokensNum:$tokensNum}')

event_json=$(exa_call_mcp "get_code_context_exa" "$arguments_json" 35)

if [[ "$JSON_MODE" -eq 1 ]]; then
  printf '%s' "$event_json" | jq --arg query "$QUERY" --argjson tokensNum "$TOKENS" '{query:$query,tokensNum:$tokensNum,searchTime:(.result.content[0]._meta.searchTime // null),text:(.result.content[0].text // "")}'
  exit 0
fi

printf '%s' "$event_json" | jq -r --arg query "$QUERY" --argjson tokensNum "$TOKENS" '
  "Exa code/context search for: " + $query + "\n"
  + "Tokens: " + ($tokensNum | tostring) + "\n"
  + (if .result.content[0]._meta.searchTime != null then "Search time: " + (.result.content[0]._meta.searchTime | tostring) + "ms\n" else "" end)
  + "\n"
  + (.result.content[0].text // "No code snippets or documentation found.")
'
