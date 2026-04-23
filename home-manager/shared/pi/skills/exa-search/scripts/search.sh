#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  search.sh "query" [--overview|--single] [--results N] [--type auto|fast|deep] [--livecrawl fallback|preferred] [--chars N] [--json]

Examples:
  search.sh "FlowRedux documentation"                                  # Broader overview (default)
  search.sh "FlowRedux documentation" --single                         # One focused Exa query
  search.sh "site:github.com freeletics FlowRedux releases" --results 5
  search.sh "latest Anthropic web search tool docs" --results 6 --chars 12000
  search.sh "FlowRedux documentation" --json
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

QUERY=""
RESULTS=5
TYPE="deep"
LIVECRAWL="preferred"
CHARS=8000
JSON_MODE=0
MODE="overview"
MAX_CONCURRENCY=2

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
    --single)
      MODE="single"
      shift
      ;;
    --overview)
      MODE="overview"
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

if ! [[ "$RESULTS" =~ ^[0-9]+$ ]] || [[ "$RESULTS" -lt 1 ]]; then
  echo "Invalid --results: $RESULTS" >&2
  exit 1
fi

if ! [[ "$CHARS" =~ ^[0-9]+$ ]] || [[ "$CHARS" -lt 1 ]]; then
  echo "Invalid --chars: $CHARS" >&2
  exit 1
fi

call_exa() {
  local label="$1"
  local query="$2"
  local payload raw data_line error_message error_code

  payload=$(jq -nc \
    --arg query "$query" \
    --arg type "$TYPE" \
    --arg livecrawl "$LIVECRAWL" \
    --argjson numResults "$RESULTS" \
    --argjson contextMaxCharacters "$CHARS" \
    '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:"web_search_exa",arguments:{query:$query,type:$type,numResults:$numResults,livecrawl:$livecrawl,contextMaxCharacters:$contextMaxCharacters}}}')

  raw=$(curl -fsSL \
    -H 'accept: application/json, text/event-stream' \
    -H 'content-type: application/json' \
    --data "$payload" \
    'https://mcp.exa.ai/mcp')

  data_line=$(printf '%s\n' "$raw" | awk '/^data: /{sub(/^data: /, ""); print; exit}')

  if [[ -z "$data_line" ]]; then
    echo "Failed to parse Exa response for query: $query" >&2
    printf '%s\n' "$raw" >&2
    return 1
  fi

  error_message=$(printf '%s' "$data_line" | jq -r '.error.message // empty')
  if [[ -n "$error_message" ]]; then
    error_code=$(printf '%s' "$data_line" | jq -r '.error.code // empty')
    if [[ -n "$error_code" ]]; then
      echo "Exa API error ($error_code) for query: $query: $error_message" >&2
    else
      echo "Exa API error for query: $query: $error_message" >&2
    fi
    return 1
  fi

  printf '%s' "$data_line" | jq -c \
    --arg label "$label" \
    --arg query "$query" \
    '{label:$label,query:$query,searchTime:(.result.content[0]._meta.searchTime // null),text:(.result.content[0].text // "")}'
}

normalize_warning_detail() {
  tr '\n' ' ' < "$1" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

normalize_topic_query() {
  printf '%s\n' "$1" \
    | sed -E 's/(^|[[:space:]])site:[^[:space:]]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//'
}

collect_batch() {
  local i batch_index label search_query result_file error_file warning

  for i in "${!batch_pids[@]}"; do
    batch_index="${batch_indexes[$i]}"
    label="${labels[$batch_index]}"
    search_query="${queries[$batch_index]}"
    result_file="${result_files[$batch_index]}"
    error_file="${error_files[$batch_index]}"

    if wait "${batch_pids[$i]}"; then
      printf '%s\n' "$(cat "$result_file")" >> "$searches_file"
    else
      warning="$label search failed: $search_query"
      if [[ -s "$error_file" ]]; then
        warning+=" ($(normalize_warning_detail "$error_file"))"
      fi
      warnings+=("$warning")
    fi
  done

  batch_pids=()
  batch_indexes=()
}

is_recency_sensitive() {
  printf '%s\n' "$1" | grep -Eiq '(^|[[:space:]])(latest|recent|new|update|updates|release|releases|announcement|announcements|changelog|today|202[0-9])([[:space:]]|$)'
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
searches_file="$tmpdir/searches.jsonl"
: > "$searches_file"

declare -a warnings=()
declare -a labels=()
declare -a queries=()
declare -a result_files=()
declare -a error_files=()
declare -a batch_pids=()
declare -a batch_indexes=()

topic_query=$(normalize_topic_query "$QUERY")
if [[ -z "$topic_query" ]]; then
  topic_query="$QUERY"
fi

if [[ "$MODE" == "single" ]]; then
  labels=("Focused search")
  queries=("$QUERY")
else
  labels=(
    "Official docs & references"
    "General overview"
    "Code, releases & issues"
  )
  queries=(
    "$topic_query official documentation docs reference"
    "$QUERY"
    "site:github.com $topic_query releases issues changelog"
  )

  if is_recency_sensitive "$QUERY"; then
    labels+=("Recent updates")
    queries+=("$topic_query latest updates announcements release notes")
  fi
fi

for i in "${!labels[@]}"; do
  result_file="$tmpdir/search-$i.json"
  error_file="$tmpdir/search-$i.err"

  result_files[i]="$result_file"
  error_files[i]="$error_file"

  call_exa "${labels[$i]}" "${queries[$i]}" > "$result_file" 2> "$error_file" &
  batch_pids+=("$!")
  batch_indexes+=("$i")

  if [[ ${#batch_pids[@]} -ge $MAX_CONCURRENCY ]]; then
    collect_batch
  fi
done

if [[ ${#batch_pids[@]} -gt 0 ]]; then
  collect_batch
fi

if [[ ! -s "$searches_file" ]]; then
  printf 'All Exa searches failed.\n' >&2
  if [[ ${#warnings[@]} -gt 0 ]]; then
    printf '%s\n' "${warnings[@]}" >&2
  fi
  exit 1
fi

warnings_json=$(if [[ ${#warnings[@]} -gt 0 ]]; then printf '%s\n' "${warnings[@]}" | jq -R . | jq -s .; else printf '[]'; fi)

if [[ "$JSON_MODE" -eq 1 ]]; then
  jq -s \
    --arg originalQuery "$QUERY" \
    --arg topicQuery "$topic_query" \
    --arg mode "$MODE" \
    --arg type "$TYPE" \
    --arg livecrawl "$LIVECRAWL" \
    --argjson results "$RESULTS" \
    --argjson contextMaxCharacters "$CHARS" \
    --argjson warnings "$warnings_json" \
    '{
      originalQuery:$originalQuery,
      topicQuery:$topicQuery,
      mode:$mode,
      settings:{type:$type,livecrawl:$livecrawl,numResultsPerSearch:$results,contextMaxCharactersPerSearch:$contextMaxCharacters},
      searches:.,
      warnings:$warnings
    }' "$searches_file"
  exit 0
fi

total_search_time=$(jq -s '[.[].searchTime // 0] | add' "$searches_file")

if [[ "$MODE" == "single" ]]; then
  echo "Exa search for: $QUERY"
else
  echo "Exa research overview for: $QUERY"
fi

echo "Mode: $MODE"
echo "Per-search settings: results=$RESULTS, type=$TYPE, livecrawl=$LIVECRAWL, chars=$CHARS"
if [[ "$total_search_time" != "null" ]]; then
  echo "Combined search time: ${total_search_time}ms"
fi

echo
echo "Search plan:"
for i in "${!labels[@]}"; do
  printf -- '- %s: %s\n' "${labels[$i]}" "${queries[$i]}"
done

if [[ ${#warnings[@]} -gt 0 ]]; then
  echo
  echo "Warnings:"
  printf '%s\n' "${warnings[@]}"
fi

echo
jq -r '
  . as $s
  | "================================================================================\n"
    + $s.label + "\n"
    + "Query: " + $s.query + "\n"
    + (if $s.searchTime != null then "Search time: " + ($s.searchTime | tostring) + "ms\n" else "" end)
    + "================================================================================\n\n"
    + $s.text
    + "\n"
' "$searches_file"
