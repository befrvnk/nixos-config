#!/usr/bin/env bash
# List mounted removable devices (under /run/media/$USER) as a JSON array of
# {name, used, size}. Used by the quickshell Storage module popup.
set -euo pipefail

mapfile -t MOUNTS < <(findmnt -rno TARGET 2>/dev/null | grep "^/run/media/$USER/" | sort)

printf "["
COUNT=${#MOUNTS[@]}
for i in "${!MOUNTS[@]}"; do
  m="${MOUNTS[$i]}"
  name=$(basename "$m")
  # df in 1K blocks -> human sizes
  read -r used size _ <<< "$(df -h "$m" 2>/dev/null | awk 'NR==2 {print $3, $2}')"
  comma=""
  [[ $((i + 1)) -lt $COUNT ]] && comma=","
  printf '{"name":"%s","used":"%s","size":"%s"}%s\n' "$name" "$used" "$size" "$comma"
done
printf ']'