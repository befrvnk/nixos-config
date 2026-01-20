#!/usr/bin/env bash
# Updates the worktrunk package to the latest GitHub release version
# Usage: ./scripts/update-worktrunk.sh

set -euo pipefail

PACKAGE_FILE="pkgs/worktrunk/package.nix"

# Get latest worktrunk release from GitHub API
echo "Fetching latest worktrunk release from GitHub..."
LATEST=$(curl -s "https://api.github.com/repos/max-sixty/worktrunk/releases/latest" | \
    jq -r '.tag_name' | \
    sed 's|^v||')

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

# Prefetch the new source from GitHub
echo "Prefetching source..."
PREFETCH_OUTPUT=$(nix run nixpkgs#nix-prefetch-github -- max-sixty worktrunk --rev "v${LATEST}" 2>/dev/null)
SRC_HASH=$(echo "$PREFETCH_OUTPUT" | jq -r '.hash')

if [[ -z "$SRC_HASH" || "$SRC_HASH" == "null" ]]; then
    echo "Error: Could not prefetch source hash"
    exit 1
fi

echo "New source hash: $SRC_HASH"

# Update version and source hash
sed -i "s|version = \".*\"|version = \"$LATEST\"|" "$PACKAGE_FILE"
sed -i "s|hash = \"sha256-.*\"|hash = \"$SRC_HASH\"|" "$PACKAGE_FILE"

echo "Updated $PACKAGE_FILE"
echo "Verifying build..."

# Verify the build works (cargoLock.lockFile means no cargo hash needed)
if nix-build --no-out-link -E 'with import <nixpkgs> {}; callPackage ./pkgs/worktrunk/package.nix {}' > /dev/null 2>&1; then
    echo "Build successful!"
else
    echo "Build failed. Please check $PACKAGE_FILE manually."
    exit 1
fi
