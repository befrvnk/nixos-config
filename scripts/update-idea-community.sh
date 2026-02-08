#!/usr/bin/env bash
# Updates the idea-community package to the latest JetBrains CDN release
# Checks EAP, RC, and release channels (prefers stable > RC > EAP)
# Usage: ./scripts/update-idea-community.sh

set -euo pipefail

PACKAGE_FILE="pkgs/idea-community/package.nix"

echo "Fetching latest IntelliJ IDEA release from JetBrains..."

# Try release first, then RC, then EAP
for TYPE in release rc eap; do
    RESPONSE=$(curl -s "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=$TYPE")
    BUILD=$(echo "$RESPONSE" | jq -r ".IIU[0].build // empty")
    VERSION=$(echo "$RESPONSE" | jq -r ".IIU[0].version // empty")
    if [[ -n "$BUILD" ]]; then
        echo "Found $TYPE: version=$VERSION build=$BUILD"
        break
    fi
done

if [[ -z "${BUILD:-}" ]]; then
    echo "Error: Could not fetch latest version from JetBrains API"
    exit 1
fi

# Get current build number from package
CURRENT=$(grep 'buildNumber = ' "$PACKAGE_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Current build: $CURRENT"

if [[ "$BUILD" == "$CURRENT" ]]; then
    echo "Already up to date!"
    exit 0
fi

# Format version string for pname
case "$TYPE" in
    eap)
        # Extract EAP number from version string (e.g., "2026.1 EAP 3" -> "2026.1-eap3")
        FORMATTED_VERSION=$(echo "$VERSION" | sed -E 's/ EAP ([0-9]+)/-eap\1/; s/ EAP/-eap/')
        ;;
    rc)
        FORMATTED_VERSION=$(echo "$VERSION" | sed -E 's/ RC ([0-9]+)/-rc\1/; s/ RC/-rc/')
        ;;
    *)
        FORMATTED_VERSION="$VERSION"
        ;;
esac

echo "Updating to $FORMATTED_VERSION (build $BUILD)..."

# Prefetch the new tarball
URL="https://download.jetbrains.com/idea/idea-${BUILD}.tar.gz"
echo "Prefetching: $URL"
HASH=$(nix-prefetch-url --unpack "$URL" 2>/dev/null | tail -1)
SRI_HASH=$(nix hash convert --hash-algo sha256 --to sri "$HASH" 2>/dev/null)

echo "New hash: $SRI_HASH"

# Update the package file
sed -i "s|buildNumber = \".*\"|buildNumber = \"$BUILD\"|" "$PACKAGE_FILE"
sed -i "s|version = \".*\"|version = \"$FORMATTED_VERSION\"|" "$PACKAGE_FILE"
sed -i "s|hash = \"sha256-.*\"|hash = \"$SRI_HASH\"|" "$PACKAGE_FILE"

echo "Updated $PACKAGE_FILE"
echo "Don't forget to test with: nix flake check --accept-flake-config"
