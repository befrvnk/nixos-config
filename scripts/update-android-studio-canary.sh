#!/usr/bin/env bash
# Updates the android-studio-canary package to the latest version from Google
# Usage: ./scripts/update-android-studio-canary.sh

set -euo pipefail

VERSION_FILE="pkgs/android-studio-canary/version.nix"
RELEASES_URL="https://jb.gg/android-studio-releases-list.xml"

echo "Fetching Android Studio releases..."

# Fetch the releases XML and save to temp file to avoid pipeline issues
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT
curl -sL "$RELEASES_URL" > "$TEMP_FILE"

# The XML structure is predictable: the first <item> with <channel>Canary</channel> is the latest
# Extract the version from the first Canary item
# Use awk for more reliable parsing
LATEST=$(awk '
    /<item>/,/<\/item>/ {
        if (/<version>/) {
            gsub(/.*<version>/, "")
            gsub(/<\/version>.*/, "")
            version = $0
        }
        if (/<channel>Canary<\/channel>/) {
            print version
            exit
        }
    }
' "$TEMP_FILE")

if [[ -z "$LATEST" ]]; then
    echo "Error: Could not fetch latest canary version from releases XML"
    exit 1
fi

echo "Latest canary version: $LATEST"

# Get current version from package
CURRENT=$(grep 'version = ' "$VERSION_FILE" | sed 's/.*"\(.*\)".*/\1/')
echo "Current version: $CURRENT"

if [[ "$LATEST" == "$CURRENT" ]]; then
    echo "Already up to date!"
    exit 0
fi

echo "Updating to $LATEST..."

# Extract the Linux download checksum from the XML
# Look for the linux.tar.gz download within the first Canary item
CHECKSUM=$(awk -v version="$LATEST" '
    /<item>/,/<\/item>/ {
        if (/<channel>Canary<\/channel>/) { in_canary = 1 }
        if (in_canary && /linux\.tar\.gz/) { in_linux = 1 }
        if (in_canary && in_linux && /<checksum>/) {
            gsub(/.*<checksum>/, "")
            gsub(/<\/checksum>.*/, "")
            print
            exit
        }
    }
' "$TEMP_FILE")

if [[ -z "$CHECKSUM" ]]; then
    echo "Warning: Could not extract checksum from releases XML, prefetching instead..."
    URL="https://dl.google.com/dl/android/studio/ide-zips/${LATEST}/android-studio-${LATEST}-linux.tar.gz"
    echo "Prefetching: $URL"
    HASH=$(nix-prefetch-url --unpack "$URL" 2>/dev/null | tail -1)
    SRI_HASH=$(nix hash to-sri --type sha256 "$HASH" 2>/dev/null)
else
    echo "Found checksum: $CHECKSUM"
    # Convert hex checksum to SRI format (sha256-base64)
    SRI_HASH=$(nix hash convert --hash-algo sha256 --to sri "$CHECKSUM" 2>/dev/null || echo "")

    if [[ -z "$SRI_HASH" ]]; then
        echo "Warning: Could not convert checksum, prefetching instead..."
        URL="https://dl.google.com/dl/android/studio/ide-zips/${LATEST}/android-studio-${LATEST}-linux.tar.gz"
        echo "Prefetching: $URL"
        HASH=$(nix-prefetch-url --unpack "$URL" 2>/dev/null | tail -1)
        SRI_HASH=$(nix hash to-sri --type sha256 "$HASH" 2>/dev/null)
    fi
fi

echo "New hash: $SRI_HASH"

# Update the version file
cat > "$VERSION_FILE" << EOF
# Android Studio Canary version info
# Updated automatically by: ./scripts/update-android-studio-canary.sh
{
  version = "$LATEST";
  hash = "$SRI_HASH";
}
EOF

echo "Updated $VERSION_FILE"
echo "Don't forget to test with: nix flake check --accept-flake-config"
