#!/usr/bin/env bash
# shellcheck source=./update-common.sh
# Updates the idea-community package to the latest JetBrains CDN release.
# Checks EAP, RC, and release channels (prefers stable > RC > EAP).
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

package_file="pkgs/idea-community/package.nix"

echo "Fetching latest IntelliJ IDEA release from JetBrains..."

for type in release rc eap; do
  response=$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=$type")
  build=$(jq -r '.IIU[0].build // empty' <<< "$response")
  version=$(jq -r '.IIU[0].version // empty' <<< "$response")
  if [[ -n "$build" ]]; then
    echo "Found $type: version=$version build=$build"
    break
  fi
done

if [[ -z "${build:-}" ]]; then
  echo "Error: Could not fetch latest version from JetBrains API"
  exit 1
fi

current=$(current_attr_value buildNumber "$package_file")
echo "Current build: $current"

if [[ "$build" == "$current" ]]; then
  echo "Already up to date!"
  exit 0
fi

case "$type" in
  eap)
    formatted_version=$(sed -E 's/ EAP ([0-9]+)/-eap\1/; s/ EAP/-eap/' <<< "$version")
    ;;
  rc)
    formatted_version=$(sed -E 's/ RC ([0-9]+)/-rc\1/; s/ RC/-rc/' <<< "$version")
    ;;
  *)
    formatted_version="$version"
    ;;
esac

echo "Updating to $formatted_version (build $build)..."

url="https://download.jetbrains.com/idea/idea-${build}.tar.gz"
sri_hash=$(prefetch_sri_hash "$url" --unpack)

echo "New hash: $sri_hash"

sed_in_place "s|buildNumber = \".*\"|buildNumber = \"$build\"|" "$package_file"
sed_in_place "s|version = \".*\"|version = \"$formatted_version\"|" "$package_file"
sed_in_place "s|hash = \"sha256-.*\"|hash = \"$sri_hash\"|" "$package_file"

echo "Updated $package_file"
echo "Don't forget to test with: nix flake check --accept-flake-config"
