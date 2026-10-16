#!/usr/bin/env bash
# Unmount (eject) removable device slot N (1-indexed) via udisks.
# Slot numbering matches storage-list.sh (sorted mounts).
set -euo pipefail
SLOT="${1:-1}"

mapfile -t MOUNTS < <(findmnt -rno TARGET 2>/dev/null | grep "^/run/media/$USER/" | sort)
INDEX=$((SLOT - 1))

if [[ $INDEX -ge 0 && $INDEX -lt ${#MOUNTS[@]} ]]; then
  MOUNT_POINT="${MOUNTS[$INDEX]}"
  BLOCK_DEVICE=$(findmnt -rno SOURCE "$MOUNT_POINT")
  if [[ -n "$BLOCK_DEVICE" ]]; then
    udisksctl unmount -b "$BLOCK_DEVICE" &>/dev/null
  fi
fi