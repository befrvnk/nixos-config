#!/usr/bin/env bash
# Updates the gh-enhance package to the latest GitHub release
# Usage: ./scripts/update-gh-enhance.sh

set -euo pipefail

PACKAGE_FILE="pkgs/gh-enhance/package.nix"
OWNER="dlvhdr"
REPO="gh-enhance"

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

# Prefetch the new source
SRC_HASH=$(nix-prefetch-url --unpack "https://github.com/$OWNER/$REPO/archive/refs/tags/$LATEST.tar.gz" 2>/dev/null | tail -1)
SRC_SRI=$(nix hash convert --hash-algo sha256 --to sri "$SRC_HASH" 2>/dev/null)

echo "New source hash: $SRC_SRI"

sed_in_place() {
    if sed --version >/dev/null 2>&1; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

# Update version and source hash
sed_in_place "s|version = \".*\"|version = \"$VERSION\"|" "$PACKAGE_FILE"
sed_in_place "/src = fetchFromGitHub/,/};/{s|hash = \"sha256-.*\"|hash = \"$SRC_SRI\"|;}" "$PACKAGE_FILE"

# Clear vendor hash to force recalculation
sed_in_place "s|vendorHash = \"sha256-.*\"|vendorHash = \"\"|" "$PACKAGE_FILE"

echo "Building to get new vendor hash..."
VENDOR_OUTPUT=$(nix-build -E "with import <nixpkgs> {}; callPackage ./$PACKAGE_FILE {}" 2>&1 || true)
VENDOR_GOT=$(echo "$VENDOR_OUTPUT" | grep "got:" | tail -1 | awk '{print $2}')

if [[ -n "$VENDOR_GOT" ]]; then
    sed_in_place "s|vendorHash = \".*\"|vendorHash = \"$VENDOR_GOT\"|" "$PACKAGE_FILE"
    echo "New vendor hash: $VENDOR_GOT"
else
    echo "⚠️  Could not determine vendor hash. Manual fix needed."
    exit 1
fi

echo "Updated $PACKAGE_FILE to $VERSION"
