#!/usr/bin/env bash
# shellcheck source=./update-common.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

flake_file="flake.nix"
lock_file="flake.lock"
checks=(
  noctalia-bar-geometry
  noctalia-tray-anchor
  noctalia-battery-warning
  noctalia-lock-auth
  noctalia-overview
)

current_tag=$(grep -o 'github:noctalia-dev/noctalia/[^"]*"' "$flake_file" | head -1 | sed 's|.*/noctalia/||; s|"$||')
if [[ -n "${1:-}" ]]; then
  new_tag="$1"
else
  new_tag=$(github_latest_release_json noctalia-dev noctalia | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
fi

if [[ -z "$new_tag" ]]; then
  echo "Could not determine the Noctalia ref to use." >&2
  exit 1
fi
if [[ "$new_tag" == "$current_tag" ]]; then
  echo "Noctalia is already pinned to $current_tag."
  exit 0
fi

backup_dir=$(mktemp -d)
cp "$flake_file" "$lock_file" "$backup_dir/"
cleanup() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "Restoring the previous Noctalia pin ($current_tag)." >&2
    cp "$backup_dir/$flake_file" "$backup_dir/$lock_file" .
  fi
  rm -rf "$backup_dir"
}
trap cleanup EXIT

echo "Bumping Noctalia $current_tag -> $new_tag"
sed_in_place "s|noctalia/${current_tag}\"|noctalia/${new_tag}\"|" "$flake_file"
nix flake lock --accept-flake-config --update-input noctalia

echo "Checking that local patches still apply and the Noctalia checks pass..."
nix build --accept-flake-config --no-link \
  .#nixosConfigurations.framework.config.home-manager.users.frank.programs.noctalia.package
for check in "${checks[@]}"; do
  echo "  $check"
  nix build --accept-flake-config --no-link ".#checks.x86_64-linux.$check"
done

echo "Noctalia is now pinned to $new_tag. Review the patch checks, then run the usual rebuild and test steps."
