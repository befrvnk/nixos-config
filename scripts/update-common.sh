#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

cd "$repo_root"

sed_in_place() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

current_attr_value() {
  local attr="$1"
  local file="$2"

  grep "${attr} = " "$file" | head -1 | sed 's/.*"\(.*\)".*/\1/'
}

github_latest_release_json() {
  local owner="$1"
  local repo="$2"

  curl -fsSL "https://api.github.com/repos/$owner/$repo/releases/latest"
}

prefetch_sri_hash() {
  local url="$1"
  local unpack_flag="${2:-}"
  local hash

  if [[ "$unpack_flag" == "--unpack" ]]; then
    hash=$(nix-prefetch-url --unpack "$url" 2>/dev/null | tail -1)
  else
    hash=$(nix-prefetch-url "$url" 2>/dev/null | tail -1)
  fi

  nix hash convert --hash-algo sha256 --to sri "$hash" 2>/dev/null
}
