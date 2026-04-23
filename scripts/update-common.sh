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

github_tag_archive_sri_hash() {
  local owner="$1"
  local repo="$2"
  local tag="$3"
  local hash=""

  if command -v nurl >/dev/null 2>&1; then
    hash=$(nurl --hash "https://github.com/$owner/$repo" "$tag" 2>/dev/null || true)
  fi

  if [[ -z "$hash" ]]; then
    hash=$(prefetch_sri_hash "https://github.com/$owner/$repo/archive/refs/tags/$tag.tar.gz" --unpack)
  fi

  echo "$hash"
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

prefetch_archive_sri_hash_keep_root() {
  local url="$1"
  local store_path
  local tmp_dir
  local hash

  store_path=$(nix store prefetch-file --json "$url" | jq -r '.storePath')
  tmp_dir=$(mktemp -d)

  case "$url" in
    *.zip)
      unzip -q "$store_path" -d "$tmp_dir"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$store_path" -C "$tmp_dir"
      ;;
    *.tar.xz)
      tar -xJf "$store_path" -C "$tmp_dir"
      ;;
    *.tar.bz2)
      tar -xjf "$store_path" -C "$tmp_dir"
      ;;
    *)
      rm -rf "$tmp_dir"
      echo "Error: Unsupported archive type for $url" >&2
      return 1
      ;;
  esac

  hash=$(nix hash path "$tmp_dir")
  rm -rf "$tmp_dir"

  echo "$hash"
}
