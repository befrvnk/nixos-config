#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./exa-mcp.sh
source "$SCRIPT_DIR/exa-mcp.sh"

usage() {
  cat <<'EOF'
Usage:
  search.sh "query" [--overview|--single] [--focus overview|docs|general|repo|recent] [--results N] [--type auto|fast|deep] [--livecrawl fallback|preferred] [--chars N] [--json]

Examples:
  search.sh "FlowRedux documentation"                                  # Broader overview (default)
  search.sh "FlowRedux documentation" --focus docs                     # Only the docs/reference pass
  search.sh "FlowRedux documentation" --single                         # One focused Exa query
  search.sh "site:github.com freeletics FlowRedux releases" --focus repo
  search.sh "latest Anthropic web search tool docs" --focus recent
  search.sh "FlowRedux documentation" --json
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

QUERY=""
RESULTS=""
TYPE=""
LIVECRAWL=""
CHARS=""
JSON_MODE=0
MODE="overview"
FOCUS="overview"
FOCUS_SET=0
MAX_CONCURRENCY=2
CURRENT_YEAR=$(date +%Y)

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
    --focus)
      FOCUS="${2:-}"
      FOCUS_SET=1
      shift 2
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

case "$FOCUS" in
  overview|docs|general|repo|recent) ;;
  *) echo "Invalid --focus: $FOCUS" >&2; exit 1 ;;
esac

if [[ "$MODE" == "single" && "$FOCUS_SET" -eq 1 ]]; then
  echo "--focus cannot be combined with --single" >&2
  exit 1
fi

normalize_warning_detail() {
  tr '\n' ' ' < "$1" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

normalize_topic_query() {
  printf '%s\n' "$1" \
    | sed -E 's/(^|[[:space:]])site:[^[:space:]]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//'
}

extract_site_filters_json() {
  local filters

  filters=$(printf '%s\n' "$1" | grep -Eo 'site:[^[:space:]]+' || true)
  if [[ -z "$filters" ]]; then
    printf '[]'
  else
    printf '%s\n' "$filters" | jq -R . | jq -s '.'
  fi
}

has_github_constraint() {
  printf '%s\n' "$1" | grep -Eiq '(^|[[:space:]])site:github\.com([[:space:]]|$)|(^|[[:space:]])github\.com([[:space:]/]|$)|(^|[[:space:]])github([[:space:]]|$)'
}

has_year_token() {
  printf '%s\n' "$1" | grep -Eq '(^|[^0-9])(19|20)[0-9]{2}([^0-9]|$)'
}

append_recent_year_if_needed() {
  local query="$1"
  if has_year_token "$query"; then
    printf '%s' "$query"
  else
    printf '%s %s' "$query" "$CURRENT_YEAR"
  fi
}

is_recency_sensitive() {
  printf '%s\n' "$1" | grep -Eiq '(^|[[:space:]])(latest|recent|new|update|updates|release|releases|announcement|announcements|changelog|today|this year|current|now|20[0-9]{2})([[:space:]]|$)'
}

apply_mode_defaults() {
  local default_results default_type default_livecrawl default_chars

  case "$MODE:$FOCUS" in
    single:*)
      default_results=8
      default_type="auto"
      default_livecrawl="fallback"
      default_chars=6000
      ;;
    overview:overview)
      default_results=5
      default_type="deep"
      default_livecrawl="preferred"
      default_chars=8000
      ;;
    overview:recent)
      default_results=6
      default_type="auto"
      default_livecrawl="preferred"
      default_chars=8000
      ;;
    overview:*)
      default_results=8
      default_type="auto"
      default_livecrawl="fallback"
      default_chars=6000
      ;;
  esac

  : "${RESULTS:=$default_results}"
  : "${TYPE:=$default_type}"
  : "${LIVECRAWL:=$default_livecrawl}"
  : "${CHARS:=$default_chars}"
}

validate_inputs() {
  case "$TYPE" in
    auto|fast|deep) ;;
    *) echo "Invalid --type: $TYPE" >&2; exit 1 ;;
  esac

  case "$LIVECRAWL" in
    fallback|preferred) ;;
    *) echo "Invalid --livecrawl: $LIVECRAWL" >&2; exit 1 ;;
  esac

  if ! [[ "$RESULTS" =~ ^[0-9]+$ ]] || (( RESULTS < 1 )); then
    echo "Invalid --results: $RESULTS" >&2
    exit 1
  fi

  if ! [[ "$CHARS" =~ ^[0-9]+$ ]] || (( CHARS < 1 )); then
    echo "Invalid --chars: $CHARS" >&2
    exit 1
  fi
}

call_exa() {
  local label="$1"
  local query="$2"
  local arguments_json event_json

  arguments_json=$(jq -nc \
    --arg query "$query" \
    --arg type "$TYPE" \
    --arg livecrawl "$LIVECRAWL" \
    --argjson numResults "$RESULTS" \
    --argjson contextMaxCharacters "$CHARS" \
    '{query:$query,type:$type,numResults:$numResults,livecrawl:$livecrawl,contextMaxCharacters:$contextMaxCharacters}')

  event_json=$(exa_call_mcp "web_search_exa" "$arguments_json" 30) || return 1

  printf '%s' "$event_json" | jq -c \
    --arg label "$label" \
    --arg query "$query" \
    '{label:$label,query:$query,searchTime:(.result.content[0]._meta.searchTime // null),text:(.result.content[0].text // "")}'
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

add_search() {
  labels+=("$1")
  queries+=("$2")
}

build_search_plan() {
  local docs_query general_query repo_query recent_base recent_query

  if [[ "$MODE" == "single" ]]; then
    add_search "Focused search" "$QUERY"
    return
  fi

  docs_query="$QUERY official documentation docs reference"
  general_query="$QUERY"

  if has_github_constraint "$QUERY"; then
    repo_query="$QUERY releases issues changelog"
  else
    repo_query="site:github.com $topic_query releases issues changelog"
  fi

  recent_base="$QUERY latest updates announcements release notes"
  recent_query=$(append_recent_year_if_needed "$recent_base")

  case "$FOCUS" in
    overview)
      add_search "Official docs & references" "$docs_query"
      add_search "General overview" "$general_query"
      add_search "Code, releases & issues" "$repo_query"
      if is_recency_sensitive "$QUERY"; then
        add_search "Recent updates" "$recent_query"
        if ! has_year_token "$recent_base"; then
          current_year_injected=1
        fi
      fi
      ;;
    docs)
      add_search "Official docs & references" "$docs_query"
      ;;
    general)
      add_search "General overview" "$general_query"
      ;;
    repo)
      add_search "Code, releases & issues" "$repo_query"
      ;;
    recent)
      add_search "Recent updates" "$recent_query"
      if ! has_year_token "$recent_base"; then
        current_year_injected=1
      fi
      ;;
  esac
}

apply_mode_defaults
validate_inputs

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

site_filters_json=$(extract_site_filters_json "$QUERY")
topic_query=$(normalize_topic_query "$QUERY")
if [[ -z "$topic_query" ]]; then
  topic_query="$QUERY"
fi
current_year_injected=0

build_search_plan

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
total_search_time=$(jq -s '[.[].searchTime // 0] | add' "$searches_file")

if [[ "$JSON_MODE" -eq 1 ]]; then
  jq -s \
    --arg originalQuery "$QUERY" \
    --arg topicQuery "$topic_query" \
    --arg mode "$MODE" \
    --arg focus "$FOCUS" \
    --arg type "$TYPE" \
    --arg livecrawl "$LIVECRAWL" \
    --argjson results "$RESULTS" \
    --argjson contextMaxCharacters "$CHARS" \
    --argjson warnings "$warnings_json" \
    --argjson siteFilters "$site_filters_json" \
    --argjson currentYearInjected "$current_year_injected" \
    ' {
      originalQuery:$originalQuery,
      topicQuery:$topicQuery,
      mode:$mode,
      focus:$focus,
      settings:{type:$type,livecrawl:$livecrawl,numResultsPerSearch:$results,contextMaxCharactersPerSearch:$contextMaxCharacters},
      siteFilters:$siteFilters,
      currentYearInjected:($currentYearInjected == 1),
      searches:.,
      warnings:$warnings
    }' "$searches_file"
  exit 0
fi

if [[ "$MODE" == "single" ]]; then
  echo "Exa search for: $QUERY"
else
  echo "Exa research overview for: $QUERY"
fi

echo "Mode: $MODE"
echo "Focus: $FOCUS"
echo "Per-search settings: results=$RESULTS, type=$TYPE, livecrawl=$LIVECRAWL, chars=$CHARS"
if [[ "$total_search_time" != "null" ]]; then
  echo "Combined search time: ${total_search_time}ms"
fi
if [[ "$current_year_injected" -eq 1 ]]; then
  echo "Recent-pass year hint: $CURRENT_YEAR"
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
