#!/usr/bin/env bash
# shellcheck source=./update-common.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

package_file="pkgs/cliamp/package.nix"

if [[ "${1:-}" == "--force" ]]; then
  sed_in_place 's|vendorHash = ".*"|vendorHash = ""|' "$package_file"
fi

echo "Updating cliamp flake input..."
nix flake update cliamp --accept-flake-config

echo "Checking cliamp vendor hash..."
get_vendor_hash_output() {
  nix build --impure --accept-flake-config --no-link --expr '
    let
      flake = builtins.getFlake (toString ./.);
      pkgs = import flake.inputs.nixpkgs {
        system = builtins.currentSystem;
        config.allowUnfree = true;
        overlays = [ (import ./overlays/cliamp.nix { cliampSrc = flake.inputs.cliamp; }) ];
      };
    in
      pkgs.cliamp.goModules
  ' 2>&1
}

build_status=0
output=$(get_vendor_hash_output) || build_status=$?

if [[ $build_status -ne 0 ]]; then
  if grep -q 'hash mismatch in fixed-output derivation' <<< "$output"; then
    new_hash=$(grep 'got:' <<< "$output" | tail -1 | awk '{print $2}')
    if [[ -n "$new_hash" ]]; then
      echo "Updating vendor hash to $new_hash..."
      sed_in_place "s|vendorHash = \".*\"|vendorHash = \"$new_hash\"|" "$package_file"
      echo "Verifying build with new vendor hash..."
      get_vendor_hash_output
      echo "cliamp vendor hash updated successfully to $new_hash."
    else
      echo "Error: Could not extract new vendor hash from nix output:" >&2
      echo "$output" >&2
      exit 1
    fi
  else
    echo "Error: Failed to evaluate/build cliamp go-modules:" >&2
    echo "$output" >&2
    exit "$build_status"
  fi
else
  echo "cliamp vendor hash is up to date."
fi
