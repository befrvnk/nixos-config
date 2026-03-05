#!/usr/bin/env bash
# Updates the ghostree package to the latest GitHub release
# Usage: ./scripts/update-ghostree.sh

set -euo pipefail

PACKAGE_FILE="pkgs/ghostree/package.nix"

echo "Fetching latest Ghostree release from GitHub..."

LATEST=$(curl -s "https://api.github.com/repos/sidequery/ghostree/releases/latest")
VERSION=$(echo "$LATEST" | jq -r '.tag_name' | sed 's/^v//')

if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
    echo "Error: Could not fetch latest version from GitHub API"
    exit 1
fi

CURRENT=$(grep 'version = ' "$PACKAGE_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Current: $CURRENT"
echo "Latest:  $VERSION"

if [[ "$VERSION" == "$CURRENT" ]]; then
    echo "Already up to date!"
    exit 0
fi

echo "Updating to $VERSION..."

URL="https://github.com/sidequery/ghostree/releases/download/v${VERSION}/Ghostree.dmg"
echo "Prefetching: $URL"
HASH=$(nix-prefetch-url "$URL" 2>/dev/null | tail -1)
SRI_HASH=$(nix hash convert --hash-algo sha256 --to sri "$HASH" 2>/dev/null)

echo "New hash: $SRI_HASH"

sed -i '' "s|version = \".*\"|version = \"$VERSION\"|" "$PACKAGE_FILE"
sed -i '' "s|hash = \"sha256-.*\"|hash = \"$SRI_HASH\"|" "$PACKAGE_FILE"

echo "Updated $PACKAGE_FILE"
