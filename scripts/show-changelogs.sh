# shellcheck shell=bash
set -euo pipefail

# Show changelog links for updated packages by comparing the current system
# profile with the previous generation.

profiles_dir="/nix/var/nix/profiles"
current="$profiles_dir/system"

shopt -s nullglob
generations=("$profiles_dir"/system-*-link)
shopt -u nullglob

if (( ${#generations[@]} < 2 )); then
  exit 0
fi

mapfile -t sorted_generations < <(printf '%s\n' "${generations[@]}" | sort -V)
previous="${sorted_generations[${#sorted_generations[@]}-2]}"

current_target=$(readlink -f "$current")
previous_target=$(readlink -f "$previous")

if [[ "$current_target" == "$previous_target" ]]; then
  exit 0
fi

echo ""
echo "Checking changelogs for updated packages..."
echo ""

changed_packages=$(nvd diff "$previous" "$current" 2>/dev/null | grep -E '^\[(U|C)' | awk '{print $3}' | cut -d: -f1 || true)

if [[ -z "$changed_packages" ]]; then
  echo "No package updates detected"
  exit 0
fi

get_changelog_url() {
  local pkg="$1"
  local url=""
  local homepage=""

  url=$(nix eval --raw "nixpkgs#$pkg.meta.changelog" 2>/dev/null || echo "")
  if [[ -n "$url" ]]; then
    echo "$url"
    return 0
  fi

  homepage=$(nix eval --raw "nixpkgs#$pkg.meta.homepage" 2>/dev/null || echo "")
  if [[ "$homepage" =~ github\.com/([^/]+)/([^/]+) ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"

    repo="${repo%.git}"
    repo="${repo%/}"
    echo "https://github.com/$owner/$repo/releases"
    return 0
  fi

  if [[ -n "$homepage" ]]; then
    echo "$homepage"
    return 0
  fi

  return 1
}

found_links=false
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue

  if url=$(get_changelog_url "$pkg"); then
    if ! $found_links; then
      echo "Changelog links:"
      found_links=true
    fi
    printf '  %s: %s\n' "$pkg" "$url"
  fi
done <<< "$changed_packages"

if ! $found_links; then
  echo "No changelog URLs found for updated packages"
fi

echo ""
