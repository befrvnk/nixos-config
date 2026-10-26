#!/usr/bin/env bash
# shellcheck source=./update-common.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

package_file="pkgs/openchamber/package.nix"
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
linux_x86_asset="OpenChamber-${version}-linux-x86_64.AppImage"
linux_arm64_asset="OpenChamber-${version}-linux-arm64.AppImage"
darwin_url=$(jq -r --arg name "$darwin_asset" '.assets[] | select(.name == $name) | .browser_download_url // empty' <<< "$release_json")
linux_x86_url=$(jq -r --arg name "$linux_x86_asset" '.assets[] | select(.name == $name) | .browser_download_url // empty' <<< "$release_json")
linux_arm64_url=$(jq -r --arg name "$linux_arm64_asset" '.assets[] | select(.name == $name) | .browser_download_url // empty' <<< "$release_json")

if [[ -z "$darwin_url" || -z "$linux_x86_url" || -z "$linux_arm64_url" ]]; then
  echo "Error: Could not find release assets for macOS, x86_64 Linux and arm64 Linux"
  exit 1
fi

darwin_hash=$(prefetch_archive_sri_hash_keep_root "$darwin_url")
linux_x86_hash=$(prefetch_sri_hash "$linux_x86_url")
linux_arm64_hash=$(prefetch_sri_hash "$linux_arm64_url")

echo "New Darwin hash: $darwin_hash"
echo "New x86_64 Linux hash: $linux_x86_hash"
echo "New arm64 Linux hash: $linux_arm64_hash"

sed_in_place "s|version = \".*\"|version = \"$version\"|" "$package_file"
sed_in_place "s|darwinHash = \"sha256-.*\"|darwinHash = \"$darwin_hash\"|" "$package_file"
sed_in_place "s|linuxX86Hash = \"sha256-.*\"|linuxX86Hash = \"$linux_x86_hash\"|" "$package_file"
sed_in_place "s|linuxArm64Hash = \"sha256-.*\"|linuxArm64Hash = \"$linux_arm64_hash\"|" "$package_file"

echo "Updated $package_file to $version"
