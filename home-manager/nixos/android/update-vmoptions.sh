#!/bin/sh
# This script finds the Android Studio configuration directory and adds the
# -Dawt.toolkit.name=WLToolkit option to the studio64.vmoptions file.
# This is to enable native Wayland support and fix blurry text issues.
set -e
for config_dir in "$HOME"/.config/Google/AndroidStudio*; do
  if [ -d "$config_dir" ]; then
    vm_options_file="$config_dir/studio64.vmoptions"
    if ! grep -q "Dawt.toolkit.name=WLToolkit" "$vm_options_file" 2>/dev/null; then
      echo "-Dawt.toolkit.name=WLToolkit" >> "$vm_options_file"
    fi
  fi
done
