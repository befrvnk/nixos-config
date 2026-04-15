#!/usr/bin/env bash
# shellcheck source=./update-common.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

package_file="pkgs/pi-coding-agent/package.nix"
owner="badlogic"
repo="pi-mono"

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

declare -A assets=(
  [x86_64-linux]=pi-linux-x64.tar.gz
  [aarch64-linux]=pi-linux-arm64.tar.gz
  [x86_64-darwin]=pi-darwin-x64.tar.gz
  [aarch64-darwin]=pi-darwin-arm64.tar.gz
)

tmp_file=$(mktemp)
cp "$package_file" "$tmp_file"

sed_in_place "s|version = \".*\";|version = \"$version\";|" "$tmp_file"

for system in x86_64-linux aarch64-linux x86_64-darwin aarch64-darwin; do
  asset="${assets[$system]}"
  digest=$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .digest // empty' <<< "$release_json")

  if [[ -z "$digest" ]]; then
    echo "Error: Could not find digest for $asset"
    rm -f "$tmp_file"
    exit 1
  fi

  sed_in_place "/$system = {/,/};/ s|hash = \"[^\"]*\";|hash = \"$digest\";|" "$tmp_file"
done

mv "$tmp_file" "$package_file"

echo "Updated $package_file to $version"
