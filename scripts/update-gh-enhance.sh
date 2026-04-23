#!/usr/bin/env bash
# shellcheck source=./update-common.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

package_file="pkgs/gh-enhance/package.nix"
owner="dlvhdr"
repo="gh-enhance"

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

src_sri=$(github_tag_archive_sri_hash "$owner" "$repo" "$latest")

echo "New source hash: $src_sri"

sed_in_place "s|version = \".*\"|version = \"$version\"|" "$package_file"
sed_in_place "/src = fetchFromGitHub/,/};/{s|hash = \"sha256-.*\"|hash = \"$src_sri\"|;}" "$package_file"
sed_in_place "s|vendorHash = \"sha256-.*\"|vendorHash = \"\"|" "$package_file"

echo "Building to get new vendor hash..."
vendor_output=$(nix-build -E "with import <nixpkgs> {}; callPackage ./$package_file {}" 2>&1 || true)
vendor_got=$(grep 'got:' <<< "$vendor_output" | tail -1 | awk '{print $2}')

if [[ -z "$vendor_got" ]]; then
  echo "Error: Could not determine vendor hash"
  exit 1
fi

sed_in_place "s|vendorHash = \".*\"|vendorHash = \"$vendor_got\"|" "$package_file"
echo "New vendor hash: $vendor_got"
echo "Updated $package_file to $version"
