# shellcheck shell=bash

set -euo pipefail

HOME=$(cd "$HOME" && pwd -P)
export HOME

usage() {
  cat <<'EOF'
Usage:
  home-cleanup [report|dry-run]
  home-cleanup clean [--all-gradle] [--projects] [--yes]

Commands:
  report       Show reclaimable space without deleting anything (default)
  dry-run      Alias for report
  clean        Show the report, ask for confirmation, then remove safe caches

Options for clean:
  --all-gradle Remove all ~/.gradle/caches instead of only build-cache-1
  --projects   Also remove Git-ignored build/ directories under ~/projects
  --yes, -y    Skip the confirmation prompt
  --help, -h   Show this help

The standard cleanup removes Android Studio generated indexes/caches,
Gradle's local build cache, Homebrew downloads, ~/.cache, and npm caches.
Android Studio or Gradle caches are skipped while the corresponding process
is running. Project cleanup only removes build/ directories confirmed ignored
by Git.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

size_kib() {
  local path="$1"
  local output

  if [ ! -e "$path" ]; then
    printf '0\n'
    return
  fi

  output=$(du -sk -- "$path" 2>/dev/null || true)
  if [ -n "$output" ]; then
    awk 'NR == 1 { print $1 }' <<<"$output"
  else
    printf '0\n'
  fi
}

sum_paths_kib() {
  local total=0
  local path
  local size

  for path in "$@"; do
    size=$(size_kib "$path")
    total=$((total + size))
  done

  printf '%s\n' "$total"
}

format_kib() {
  local kib="$1"
  numfmt --to=iec-i --suffix=B "$((kib * 1024))"
}

print_size() {
  local label="$1"
  local kib="$2"
  printf '  %-47s %10s\n' "$label" "$(format_kib "$kib")"
}

android_studio_running() {
  /usr/bin/pgrep -f 'Android Studio.*\.app/Contents/MacOS/studio' >/dev/null 2>&1
}

gradle_running() {
  /usr/bin/pgrep -f 'org\.gradle\.launcher\.daemon\.bootstrap\.GradleDaemon' >/dev/null 2>&1
}

safe_remove() {
  local path="$1"

  case "$path" in
    "$HOME"/*) ;;
    *) die "refusing to remove path outside the home directory: $path" ;;
  esac

  [ "$path" != "$HOME" ] || die "refusing to remove the home directory"
  rm -rf -- "$path"
}

is_ignored_build_dir() {
  local build_dir="$1"
  local root
  local relative

  root=$(git -C "$(dirname "$build_dir")" rev-parse --show-toplevel 2>/dev/null) || return 1
  case "$build_dir" in
    "$root"/*) ;;
    *) return 1 ;;
  esac

  relative=${build_dir#"$root"/}
  git -C "$root" check-ignore -q -- "$relative/"
}

ANDROID_CACHE_PATHS=()
PROJECT_BUILD_PATHS=()
NPM_CACHE_PATHS=()

shopt -s nullglob
for android_root in "$HOME/Library/Caches/Google"/AndroidStudio*; do
  [ -d "$android_root/caches" ] && ANDROID_CACHE_PATHS+=("$android_root/caches")
  [ -d "$android_root/index" ] && ANDROID_CACHE_PATHS+=("$android_root/index")
done
for npm_cache in "$HOME/.npm/_cacache" "$HOME/.npm/_npx"; do
  [ -e "$npm_cache" ] && NPM_CACHE_PATHS+=("$npm_cache")
done
shopt -u nullglob

PROJECTS_ROOT="$HOME/projects"
if [ -d "$PROJECTS_ROOT" ]; then
  while IFS= read -r -d '' build_dir; do
    if is_ignored_build_dir "$build_dir"; then
      PROJECT_BUILD_PATHS+=("$build_dir")
    fi
  done < <(
    find "$PROJECTS_ROOT" \
      \( -name .git -o -name .gradle -o -name .kotlin -o -name .devenv -o -name .direnv -o -name node_modules \) -prune -o \
      -type d -name build -print0 -prune 2>/dev/null
  )
fi

ANDROID_KIB=0
if [ "${#ANDROID_CACHE_PATHS[@]}" -gt 0 ]; then
  ANDROID_KIB=$(sum_paths_kib "${ANDROID_CACHE_PATHS[@]}")
fi
GRADLE_BUILD_CACHE="$HOME/.gradle/caches/build-cache-1"
GRADLE_BUILD_KIB=$(size_kib "$GRADLE_BUILD_CACHE")
GRADLE_ALL_CACHE="$HOME/.gradle/caches"
GRADLE_ALL_KIB=$(size_kib "$GRADLE_ALL_CACHE")
GRADLE_EXTRA_KIB=$((GRADLE_ALL_KIB - GRADLE_BUILD_KIB))
[ "$GRADLE_EXTRA_KIB" -ge 0 ] || GRADLE_EXTRA_KIB=0
HOMEBREW_CACHE="$HOME/Library/Caches/Homebrew/downloads"
HOMEBREW_KIB=$(size_kib "$HOMEBREW_CACHE")
USER_CACHE="$HOME/.cache"
USER_CACHE_KIB=$(size_kib "$USER_CACHE")
NPM_KIB=0
if [ "${#NPM_CACHE_PATHS[@]}" -gt 0 ]; then
  NPM_KIB=$(sum_paths_kib "${NPM_CACHE_PATHS[@]}")
fi
PROJECT_BUILD_KIB=0
if [ "${#PROJECT_BUILD_PATHS[@]}" -gt 0 ]; then
  PROJECT_BUILD_KIB=$(sum_paths_kib "${PROJECT_BUILD_PATHS[@]}")
fi
STANDARD_KIB=$((ANDROID_KIB + GRADLE_BUILD_KIB + HOMEBREW_KIB + USER_CACHE_KIB + NPM_KIB))
AGGRESSIVE_KIB=$((STANDARD_KIB + GRADLE_EXTRA_KIB + PROJECT_BUILD_KIB))

print_report() {
  printf 'Reclaimable home-directory space\n\n'
  printf 'Standard cleanup:\n'
  print_size "Android Studio generated indexes/caches" "$ANDROID_KIB"
  print_size "Gradle local build cache" "$GRADLE_BUILD_KIB"
  print_size "Homebrew downloads" "$HOMEBREW_KIB"
  print_size "User tool caches (~/.cache)" "$USER_CACHE_KIB"
  print_size "npm caches" "$NPM_KIB"
  printf '  %s\n' '-----------------------------------------------------------'
  print_size "Standard total" "$STANDARD_KIB"

  printf '\nOptional cleanup:\n'
  print_size "Other Gradle caches (--all-gradle)" "$GRADLE_EXTRA_KIB"
  print_size "Git-ignored project build directories (--projects)" "$PROJECT_BUILD_KIB"
  printf '  %s\n' '-----------------------------------------------------------'
  print_size "Maximum selected by all options" "$AGGRESSIVE_KIB"

  printf '\nSafety status:\n'
  if android_studio_running; then
    printf '  Android Studio is running; its cache cleanup will be skipped.\n'
  else
    printf '  Android Studio is not running.\n'
  fi
  if gradle_running; then
    printf '  A Gradle daemon is running; Gradle cleanup will be skipped.\n'
  else
    printf '  No Gradle daemon is running.\n'
  fi
  printf '  Project cleanup found %d Git-ignored build directories.\n' "${#PROJECT_BUILD_PATHS[@]}"
}

command=${1:-report}
if [ "$#" -gt 0 ]; then
  shift
fi

case "$command" in
  report | dry-run)
    [ "$#" -eq 0 ] || die "$command does not accept options"
    print_report
    exit 0
    ;;
  clean) ;;
  help | --help | -h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "unknown command: $command"
    ;;
esac

all_gradle=false
clean_projects=false
assume_yes=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all-gradle) all_gradle=true ;;
    --projects) clean_projects=true ;;
    --yes | -y) assume_yes=true ;;
    --help | -h)
      usage
      exit 0
      ;;
    *) die "unknown option for clean: $1" ;;
  esac
  shift
done

print_report
selected_kib=$STANDARD_KIB
if "$all_gradle"; then
  selected_kib=$((selected_kib + GRADLE_EXTRA_KIB))
fi
if "$clean_projects"; then
  selected_kib=$((selected_kib + PROJECT_BUILD_KIB))
fi

printf '\nSelected cleanup: %s\n' "$(format_kib "$selected_kib")"
if ! "$assume_yes"; then
  if [ ! -t 0 ]; then
    die "confirmation requires a terminal; pass --yes to run non-interactively"
  fi
  read -r -p 'Continue? [y/N] ' answer
  case "$answer" in
    y | Y | yes | YES) ;;
    *)
      printf 'Cancelled.\n'
      exit 0
      ;;
  esac
fi

CLEANED_KIB=0

if [ "$ANDROID_KIB" -gt 0 ]; then
  if android_studio_running; then
    printf 'Skipping Android Studio caches because Android Studio is running.\n' >&2
  else
    printf 'Removing Android Studio generated indexes/caches...\n'
    for path in "${ANDROID_CACHE_PATHS[@]}"; do
      safe_remove "$path"
    done
    CLEANED_KIB=$((CLEANED_KIB + ANDROID_KIB))
  fi
fi

selected_gradle_kib=$GRADLE_BUILD_KIB
selected_gradle_path=$GRADLE_BUILD_CACHE
if "$all_gradle"; then
  selected_gradle_kib=$GRADLE_ALL_KIB
  selected_gradle_path=$GRADLE_ALL_CACHE
fi
if [ "$selected_gradle_kib" -gt 0 ]; then
  if gradle_running; then
    printf 'Skipping Gradle caches because a Gradle daemon is running.\n' >&2
    printf 'Stop active builds and run ./gradlew --stop, then run this command again.\n' >&2
  else
    printf 'Removing Gradle caches...\n'
    safe_remove "$selected_gradle_path"
    CLEANED_KIB=$((CLEANED_KIB + selected_gradle_kib))
  fi
fi

if [ "$HOMEBREW_KIB" -gt 0 ]; then
  printf 'Removing Homebrew downloads...\n'
  safe_remove "$HOMEBREW_CACHE"
  CLEANED_KIB=$((CLEANED_KIB + HOMEBREW_KIB))
fi

if [ "$USER_CACHE_KIB" -gt 0 ]; then
  printf 'Removing user tool caches...\n'
  safe_remove "$USER_CACHE"
  CLEANED_KIB=$((CLEANED_KIB + USER_CACHE_KIB))
fi

if [ "$NPM_KIB" -gt 0 ]; then
  printf 'Removing npm caches...\n'
  for path in "${NPM_CACHE_PATHS[@]}"; do
    safe_remove "$path"
  done
  CLEANED_KIB=$((CLEANED_KIB + NPM_KIB))
fi

if "$clean_projects" && [ "$PROJECT_BUILD_KIB" -gt 0 ]; then
  printf 'Removing Git-ignored project build directories...\n'
  for build_dir in "${PROJECT_BUILD_PATHS[@]}"; do
    if is_ignored_build_dir "$build_dir"; then
      safe_remove "$build_dir"
    else
      printf 'Skipping directory no longer confirmed ignored by Git: %s\n' "$build_dir" >&2
    fi
  done
  CLEANED_KIB=$((CLEANED_KIB + PROJECT_BUILD_KIB))
fi

printf '\nCleanup complete. Targeted %s of files.\n' "$(format_kib "$CLEANED_KIB")"
printf 'Run home-cleanup again to measure what remains.\n'
