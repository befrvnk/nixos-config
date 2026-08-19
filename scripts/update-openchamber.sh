#!/usr/bin/env bash
# shellcheck source=./update-common.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

package_file="pkgs/openchamber/package.nix"
hermi_file="hosts/hermi/default.nix"
owner="openchamber"
repo="openchamber"

echo "Fetching latest $repo release from GitHub..."

release_json=$(github_latest_release_json "$owner" "$repo")
latest=$(jq -r '.tag_name // empty' <<< "$release_json")

if [[ -z "$latest" ]]; then
  echo "Error: Could not fetch latest version from GitHub API"
  exit 1
fi

version="${latest#v}"
current=$(current_attr_value version "$package_file")

echo "Current: $current, Latest: $version"

if [[ "$version" == "$current" ]]; then
  echo "Already up to date!"
  exit 0
fi

darwin_asset="OpenChamber-${version}-mac-arm64.zip"
linux_asset="OpenChamber-${version}-linux-x86_64.AppImage"
darwin_url=$(jq -r --arg name "$darwin_asset" '.assets[] | select(.name == $name) | .browser_download_url // empty' <<< "$release_json")
linux_url=$(jq -r --arg name "$linux_asset" '.assets[] | select(.name == $name) | .browser_download_url // empty' <<< "$release_json")

if [[ -z "$darwin_url" || -z "$linux_url" ]]; then
  echo "Error: Could not find release assets for macOS and x86_64 Linux"
  exit 1
fi

darwin_hash=$(prefetch_archive_sri_hash_keep_root "$darwin_url")
linux_hash=$(prefetch_sri_hash "$linux_url")

echo "New Darwin hash: $darwin_hash"
echo "New Linux hash: $linux_hash"

sed_in_place "s|version = \".*\"|version = \"$version\"|" "$package_file"
sed_in_place "s|darwinHash = \"sha256-.*\"|darwinHash = \"$darwin_hash\"|" "$package_file"
sed_in_place "s|linuxHash = \"sha256-.*\"|linuxHash = \"$linux_hash\"|" "$package_file"
sed_in_place "s|openchamberVersion = \".*\"|openchamberVersion = \"$version\"|" "$hermi_file"

echo "Updated $package_file and $hermi_file to $version"
