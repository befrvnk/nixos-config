#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mapfile -t tests < <(find home-manager/shared/pi/extensions \( -name '*.test.ts' -o -name '*.test.mjs' \) | sort)

if [ "${#tests[@]}" -eq 0 ]; then
  echo "No pi extension tests found." >&2
  exit 1
fi

nix shell nixpkgs#tsx --command tsx --test "${tests[@]}"
