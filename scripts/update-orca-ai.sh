#!/usr/bin/env bash
# shellcheck source=./update-common.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

linux_package_file="pkgs/orca-ai/package.nix"
darwin_package_file="pkgs/orca-ai/darwin.nix"
owner="stablyai"
repo="orca"

echo "Fetching latest $repo release from GitHub..."

release_json=$(github_latest_release_json "$owner" "$repo")
latest=$(jq -r '.tag_name // empty' <<< "$release_json")

if [[ -z "$latest" ]]; then
  echo "Error: Could not fetch latest version from GitHub API"
  exit 1
fi

version="${latest#v}"
linux_current=$(current_attr_value version "$linux_package_file")
darwin_current=$(current_attr_value version "$darwin_package_file")

echo "Linux current: $linux_current, Darwin current: $darwin_current, Latest: $version"

if [[ "$version" == "$linux_current" && "$version" == "$darwin_current" ]]; then
  echo "Already up to date!"
  exit 0
fi

asset_url() {
  local name="$1"

  jq -r --arg name "$name" '.assets[] | select(.name == $name) | .browser_download_url // empty' <<< "$release_json"
}

asset_digest_sri() {
  local name="$1"
  local digest

  digest=$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .digest // empty' <<< "$release_json")
  if [[ "$digest" == sha256:* ]]; then
    nix hash convert --hash-algo sha256 --to sri "${digest#sha256:}" 2>/dev/null || true
  fi
}

linux_asset="orca-ide_${version}_amd64.deb"
linux_url=$(asset_url "$linux_asset")

if [[ -z "$linux_url" ]]; then
  echo "Error: Could not find asset $linux_asset"
  exit 1
fi

linux_sri=$(asset_digest_sri "$linux_asset")
if [[ -z "$linux_sri" ]]; then
  linux_sri=$(prefetch_sri_hash "$linux_url")
fi

echo "Linux hash: $linux_sri"

sed_in_place "s|version = \".*\";|version = \"$version\";|" "$linux_package_file"
sed_in_place "s|hash = \"sha256-.*\";|hash = \"$linux_sri\";|" "$linux_package_file"

for system in aarch64-darwin x86_64-darwin; do
  case "$system" in
    aarch64-darwin) asset="Orca-${version}-arm64-mac.zip" ;;
    x86_64-darwin) asset="Orca-${version}-mac.zip" ;;
  esac

  url=$(asset_url "$asset")
  if [[ -z "$url" ]]; then
    echo "Error: Could not find asset $asset"
    exit 1
  fi

  sri=$(prefetch_sri_hash "$url" --unpack)
  echo "$system hash: $sri"

  sed_in_place "/$system = fetchzip {/,/};/ s|hash = \"sha256-.*\";|hash = \"$sri\";|" "$darwin_package_file"
done

sed_in_place "s|version = \".*\";|version = \"$version\";|" "$darwin_package_file"

echo "Updated $linux_package_file and $darwin_package_file to $version"
