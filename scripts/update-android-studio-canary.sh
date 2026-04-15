#!/usr/bin/env bash
# shellcheck source=./update-common.sh
# Updates the android-studio-canary package to the latest version from Google.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

version_file="pkgs/android-studio-canary/version.nix"
releases_url="https://jb.gg/android-studio-releases-list.xml"

echo "Fetching Android Studio releases..."

temp_file=$(mktemp)
trap 'rm -f "$temp_file"' EXIT
curl -fsSL "$releases_url" > "$temp_file"

read -r latest linux_url < <(
  awk '
    /<item>/,/<\/item>/ {
      if (/<version>/) {
        gsub(/.*<version>/, "")
        gsub(/<\/version>.*/, "")
        version = $0
      }
      if (/<channel>Canary<\/channel>/) {
        in_canary = 1
      }
      if (in_canary && /<link>.*linux\.tar\.gz/) {
        gsub(/.*<link>/, "")
        gsub(/<\/link>.*/, "")
        linux_url = $0
      }
      if (in_canary && /<checksum>/ && linux_url != "") {
        print version, linux_url
        exit
      }
    }
  ' "$temp_file"
)

if [[ -z "$latest" ]]; then
  echo "Error: Could not fetch latest canary version from releases XML"
  exit 1
fi

echo "Latest canary version: $latest"
echo "Download URL: $linux_url"

current=$(current_attr_value version "$version_file")
echo "Current version: $current"

if [[ "$latest" == "$current" ]]; then
  echo "Already up to date!"
  exit 0
fi

checksum=$(awk '
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
' "$temp_file")

if [[ -n "$checksum" ]]; then
  sri_hash=$(nix hash convert --hash-algo sha256 --to sri "$checksum" 2>/dev/null || true)
else
  sri_hash=""
fi

if [[ -z "$sri_hash" ]]; then
  echo "Prefetching archive to determine hash..."
  sri_hash=$(prefetch_sri_hash "$linux_url")
fi

echo "New hash: $sri_hash"

download_url="${linux_url//https:\/\/edgedl.me.gvt1.com\/android\/studio\//https:\/\/dl.google.com\/dl\/android\/studio\/}"

echo "Normalized URL: $download_url"

cat > "$version_file" <<EOF
# Android Studio Canary version info
# Updated automatically by: ./scripts/update-android-studio-canary.sh
{
  version = "$latest";
  hash = "$sri_hash";
  url = "$download_url";
}
EOF

echo "Updated $version_file"
echo "Don't forget to test with: nix flake check --accept-flake-config"
