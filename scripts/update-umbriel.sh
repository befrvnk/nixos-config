#!/usr/bin/env bash
# shellcheck source=./update-common.sh
# Keeps the `umbriel` flake input pinned to the revision nixpkgs builds, so the
# umbriel-trial assertion stays green after `nix flake update`.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/update-common.sh"

flake_file="flake.nix"
input_prefix="github:noctalia-dev/umbriel/"

echo "Reading the umbriel revision built by nixpkgs..."
# Resolve nixpkgs from flake.lock instead of `builtins.getFlake ./.`, so the script
# still runs when our own flake inputs are broken. Umbriel is Linux-only, so evaluate
# it for the framework system rather than the current one; the script then also works
# from macOS.
# The expression is Nix, not shell, so the `${...}` interpolation is intentional.
# shellcheck disable=SC2016
nixpkgs_rev=$(
  nix eval --raw --impure --accept-flake-config --expr '
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      node = lock.nodes.${lock.nodes.root.inputs.nixpkgs};
      pkgs = (builtins.getFlake "github:NixOS/nixpkgs/${node.locked.rev}").legacyPackages.x86_64-linux;
    in
      if builtins.hasAttr "umbriel" pkgs then (pkgs.umbriel.src.drvAttrs.rev or "") else ""'
)

if [[ -z "$nixpkgs_rev" ]]; then
  echo "Error: could not read the umbriel source revision from nixpkgs." >&2
  exit 1
fi

current_rev=$(grep -o "${input_prefix}[0-9a-f]*" "$flake_file" | head -n 1 | sed "s|${input_prefix}||")

if [[ -z "$current_rev" ]]; then
  echo "Error: no ${input_prefix}<rev> entry found in $flake_file." >&2
  exit 1
fi

if [[ "$current_rev" == "$nixpkgs_rev" ]]; then
  echo "umbriel flake input already matches nixpkgs ($nixpkgs_rev)."
  exit 0
fi

echo "Pinning umbriel input: $current_rev -> $nixpkgs_rev"
sed_in_place "s|${input_prefix}[0-9a-f]*|${input_prefix}${nixpkgs_rev}|" "$flake_file"
nix flake update umbriel --accept-flake-config

locked_rev=$(
  nix eval --raw --impure --expr '(builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.umbriel.locked.rev'
)

if [[ "$locked_rev" != "$nixpkgs_rev" ]]; then
  echo "Error: flake.lock pins umbriel at $locked_rev, expected $nixpkgs_rev." >&2
  exit 1
fi

echo "umbriel flake input synced to $locked_rev."
