# Show changelog links for updated packages
# This script is sourced by show-changelogs.nix which injects $nvd, $nix, $grep, $awk, $cut

# Get the latest two system generations
profiles_dir="/nix/var/nix/profiles"
current="$profiles_dir/system"

# Find previous generation (second-to-last in sorted list)
previous=$(ls -1d "$profiles_dir"/system-*-link 2>/dev/null | sort -V | tail -n 2 | head -n 1)

if [[ -z "$previous" ]] || [[ ! -e "$previous" ]]; then
  # No previous generation to compare
  exit 0
fi

# Skip if current and previous are the same
current_target=$(readlink -f "$current")
previous_target=$(readlink -f "$previous")

if [[ "$current_target" == "$previous_target" ]]; then
  exit 0
fi

echo ""
echo "Checking changelogs for updated packages..."
echo ""

# Get changed packages from nvd ([U]=upgrade, [C]=changed multi-output)
changed_packages=$("$nvd" diff "$previous" "$current" 2>/dev/null | "$grep" -E '^\[(U|C)' | "$awk" '{print $3}' | "$cut" -d: -f1 || true)

if [[ -z "$changed_packages" ]]; then
  echo "No package updates detected"
  exit 0
fi

# Function to get changelog URL for a package
get_changelog_url() {
  local pkg="$1"
  local url=""

  # Strategy 1: Try meta.changelog
  url=$("$nix" eval --raw "nixpkgs#$pkg.meta.changelog" 2>/dev/null || echo "")
  if [[ -n "$url" ]]; then
    echo "$url"
    return 0
  fi

  # Strategy 2: Try meta.homepage and check if it's GitHub
  local homepage
  homepage=$("$nix" eval --raw "nixpkgs#$pkg.meta.homepage" 2>/dev/null || echo "")
  if [[ "$homepage" =~ github\.com/([^/]+)/([^/]+) ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    # Remove potential .git suffix or trailing slash
    repo="${repo%.git}"
    repo="${repo%/}"
    echo "https://github.com/$owner/$repo/releases"
    return 0
  fi

  # Strategy 3: If homepage exists but not GitHub, return it
  if [[ -n "$homepage" ]]; then
    echo "$homepage"
    return 0
  fi

  return 1
}

# Process each changed package
found_links=false
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue

  if url=$(get_changelog_url "$pkg"); then
    if ! $found_links; then
      echo "Changelog links:"
      found_links=true
    fi
    printf "  %s: %s\n" "$pkg" "$url"
  fi
done <<< "$changed_packages"

if ! $found_links; then
  echo "No changelog URLs found for updated packages"
fi

echo ""
