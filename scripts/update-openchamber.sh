#!/usr/bin/env bash
# Updates the openchamber package to the latest GitHub release
# Usage: ./scripts/update-openchamber.sh

set -euo pipefail

PACKAGE_FILE="pkgs/openchamber/package.nix"
OWNER="openchamber"
REPO="openchamber"

echo "Fetching latest $REPO release from GitHub..."

LATEST=$(curl -s "https://api.github.com/repos/$OWNER/$REPO/releases/latest" | jq -r '.tag_name // empty')

if [[ -z "$LATEST" ]]; then
    echo "Error: Could not fetch latest version from GitHub API"
    exit 1
fi

# Strip v prefix for version comparison
VERSION="${LATEST#v}"
CURRENT=$(grep 'version = ' "$PACKAGE_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')

echo "Current: $CURRENT, Latest: $VERSION"

if [[ "$VERSION" == "$CURRENT" ]]; then
    echo "Already up to date!"
    exit 0
fi

echo "Updating to $VERSION..."

# Prefetch the new tarball
URL="https://github.com/$OWNER/$REPO/releases/download/v${VERSION}/OpenChamber.app-darwin-aarch64.tar.gz"
SRC_HASH=$(nix-prefetch-url "$URL" 2>/dev/null | tail -1)
SRC_SRI=$(nix hash convert --hash-algo sha256 --to sri "$SRC_HASH" 2>/dev/null)

echo "New hash: $SRC_SRI"

# Update version and hash
sed -i "s|version = \".*\"|version = \"$VERSION\"|" "$PACKAGE_FILE"
sed -i "s|hash = \"sha256-.*\"|hash = \"$SRC_SRI\"|" "$PACKAGE_FILE"

echo "Updated $PACKAGE_FILE to $VERSION"
