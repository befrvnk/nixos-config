#!/usr/bin/env bash

set -euo pipefail

PACKAGE_FILE="pkgs/pi-coding-agent/package.nix"
OWNER="badlogic"
REPO="pi-mono"

echo "Fetching latest $REPO release from GitHub..."

release_json=$(gh api "repos/$OWNER/$REPO/releases/latest")
latest=$(jq -r '.tag_name // empty' <<< "$release_json")

if [[ -z "$latest" ]]; then
  echo "Error: Could not fetch latest version from GitHub API"
  exit 1
fi

version="${latest#v}"
current=$(grep 'version = ' "$PACKAGE_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')

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
cp "$PACKAGE_FILE" "$tmp_file"

sed -i "s|version = \".*\";|version = \"$version\";|" "$tmp_file"

for system in x86_64-linux aarch64-linux x86_64-darwin aarch64-darwin; do
  asset="${assets[$system]}"
  digest=$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .digest // empty' <<< "$release_json")

  if [[ -z "$digest" ]]; then
    echo "Error: Could not find digest for $asset"
    rm -f "$tmp_file"
    exit 1
  fi

  sed -i "/$system = {/,/};/ s|hash = \"sha256-.*\";|hash = \"$digest\";|" "$tmp_file"
done

mv "$tmp_file" "$PACKAGE_FILE"

echo "Updated $PACKAGE_FILE to $version"
