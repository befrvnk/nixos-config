#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

tests=()
while IFS= read -r test_file; do
  tests[${#tests[@]}]="$test_file"
done < <(find home-manager/shared/pi/extensions \( -name '*.test.ts' -o -name '*.test.mjs' \) | sort)

if [ "${#tests[@]}" -eq 0 ]; then
  echo "No pi extension tests found." >&2
  exit 1
fi

nix shell --accept-flake-config nixpkgs#tsx --command \
  tsx --test --test-concurrency=1 "${tests[@]}"
