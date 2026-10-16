#!/usr/bin/env bash
# Open removable device slot N (1-indexed) in the file manager.
# Slot numbering matches storage-list.sh (sorted mounts).
set -euo pipefail
SLOT="${1:-1}"

mapfile -t MOUNTS < <(findmnt -rno TARGET 2>/dev/null | grep "^/run/media/$USER/" | sort)
INDEX=$((SLOT - 1))

if [[ $INDEX -ge 0 && $INDEX -lt ${#MOUNTS[@]} ]]; then
  nautilus "${MOUNTS[$INDEX]}" &
fi