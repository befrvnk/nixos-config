#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  search.sh "query" [--results N] [--type auto|fast|deep] [--livecrawl fallback|preferred] [--chars N] [--json]

Examples:
  search.sh "FlowRedux documentation"
  search.sh "site:github.com freeletics FlowRedux releases" --results 5 --type deep
  search.sh "latest Anthropic web search tool docs" --livecrawl preferred
  search.sh "FlowRedux documentation" --json
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

QUERY=""
RESULTS=8
TYPE="auto"
LIVECRAWL="fallback"
CHARS=10000
JSON_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --results)
      RESULTS="${2:-}"
      shift 2
      ;;
    --type)
      TYPE="${2:-}"
      shift 2
      ;;
    --livecrawl)
      LIVECRAWL="${2:-}"
      shift 2
      ;;
    --chars|--context-max-characters)
      CHARS="${2:-}"
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

case "$TYPE" in
  auto|fast|deep) ;;
  *) echo "Invalid --type: $TYPE" >&2; exit 1 ;;
esac

case "$LIVECRAWL" in
  fallback|preferred) ;;
  *) echo "Invalid --livecrawl: $LIVECRAWL" >&2; exit 1 ;;
esac

PAYLOAD=$(jq -nc \
  --arg query "$QUERY" \
  --arg type "$TYPE" \
  --arg livecrawl "$LIVECRAWL" \
  --argjson numResults "$RESULTS" \
  --argjson contextMaxCharacters "$CHARS" \
  '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:"web_search_exa",arguments:{query:$query,type:$type,numResults:$numResults,livecrawl:$livecrawl,contextMaxCharacters:$contextMaxCharacters}}}')

RAW=$(curl -fsSL \
  -H 'accept: application/json, text/event-stream' \
  -H 'content-type: application/json' \
  --data "$PAYLOAD" \
  'https://mcp.exa.ai/mcp')

DATA_LINE=$(printf '%s\n' "$RAW" | awk '/^data: /{sub(/^data: /, ""); print; exit}')

if [[ -z "$DATA_LINE" ]]; then
  echo "Failed to parse Exa response" >&2
  printf '%s\n' "$RAW" >&2
  exit 1
fi

TEXT=$(printf '%s' "$DATA_LINE" | jq -r '.result.content[0].text // empty')
SEARCH_TIME=$(printf '%s' "$DATA_LINE" | jq -r '.result.content[0]._meta.searchTime // empty')

if [[ "$JSON_MODE" -eq 1 ]]; then
  printf '%s' "$DATA_LINE" | jq .
  exit 0
fi

if [[ -n "$SEARCH_TIME" && "$SEARCH_TIME" != "null" ]]; then
  echo "Exa search for: $QUERY"
  echo "Search time: ${SEARCH_TIME}ms"
  echo
else
  echo "Exa search for: $QUERY"
  echo
fi

printf '%s\n' "$TEXT"
