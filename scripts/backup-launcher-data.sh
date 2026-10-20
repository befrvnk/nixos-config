#!/usr/bin/env bash
set -euo pipefail
umask 077

backup_root="${HOME}/launcher-backups"
mkdir -p "$backup_root"
backup_dir="$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S)-XXXXXX")"

paths=(
  ".config/org.asyar.app"
  ".config/asyar"
  ".config/vicinae"
  ".local/share/org.asyar.app"
  ".local/share/asyar"
  ".local/share/vicinae"
  ".local/state/vicinae"
  "Library/Application Support/org.asyar.app"
  "Library/Caches/org.asyar.app"
  "Library/HTTPStorages/org.asyar.app"
  "Library/Preferences/org.asyar.app.plist"
  "Library/Saved Application State/org.asyar.app.savedState"
  "Library/WebKit/org.asyar.app"
)
existing=()
for path in "${paths[@]}"; do
  if [[ -e "$HOME/$path" ]]; then
    existing+=("$path")
  fi
done

if (( ${#existing[@]} == 0 )); then
  rmdir "$backup_dir"
  echo "No launcher data found; no archive created."
  exit 0
fi

# Follow Home Manager links so the backup survives Nix garbage collection.
tar -chzf "$backup_dir/launcher-data.tar.gz" -C "$HOME" "${existing[@]}"
echo "Launcher data saved to $backup_dir/launcher-data.tar.gz"
