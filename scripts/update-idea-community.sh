#!/usr/bin/env bash
# Updates the idea-community package to the latest GitHub release version
# Usage: ./scripts/update-idea-community.sh

set -euo pipefail

PACKAGE_FILE="pkgs/idea-community/package.nix"

# Get latest IDEA release from GitHub API
echo "Fetching latest IntelliJ IDEA release from GitHub..."
LATEST=$(curl -s "https://api.github.com/repos/JetBrains/intellij-community/releases" | \
    jq -r '[.[] | select(.tag_name | startswith("idea/"))] | .[0].tag_name' | \
    sed 's|idea/||')

if [[ -z "$LATEST" || "$LATEST" == "null" ]]; then
    echo "Error: Could not fetch latest version from GitHub API"
    exit 1
fi

echo "Latest version: $LATEST"

# Get current version from package
CURRENT=$(grep 'version = ' "$PACKAGE_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Current version: $CURRENT"

if [[ "$LATEST" == "$CURRENT" ]]; then
    echo "Already up to date!"
    exit 0
fi

echo "Updating to $LATEST..."

# Prefetch the new tarball
URL="https://github.com/JetBrains/intellij-community/releases/download/idea/${LATEST}/idea-${LATEST}.tar.gz"
echo "Prefetching: $URL"
HASH=$(nix-prefetch-url --unpack "$URL" 2>/dev/null | tail -1)
SRI_HASH=$(nix hash to-sri --type sha256 "$HASH" 2>/dev/null)

echo "New hash: $SRI_HASH"

# Update the package file
sed -i "s|version = \".*\"|version = \"$LATEST\"|" "$PACKAGE_FILE"
sed -i "s|hash = \"sha256-.*\"|hash = \"$SRI_HASH\"|" "$PACKAGE_FILE"

echo "Updated $PACKAGE_FILE"
echo "Don't forget to test with: nix flake check --accept-flake-config"
