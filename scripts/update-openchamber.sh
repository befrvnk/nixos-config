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

url="https://github.com/$owner/$repo/releases/download/v${version}/OpenChamber.app-darwin-aarch64.tar.gz"
src_sri=$(prefetch_sri_hash "$url")

echo "New hash: $src_sri"

sed_in_place "s|version = \".*\"|version = \"$version\"|" "$package_file"
sed_in_place "s|hash = \"sha256-.*\"|hash = \"$src_sri\"|" "$package_file"

echo "Updated $package_file to $version"
