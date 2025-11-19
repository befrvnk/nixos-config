# Custom rebuild function for NixOS
#
# This function wraps 'nh os' to provide a convenient way to
# build and switch configurations. Uses 'nh' (Nix Helper) for better
# progress output, faster builds, and visual diffs of package changes.
#
# Usage:
#   rebuild [switch] [nh-options]
#
# Arguments:
#   switch: (Optional) If provided, the action will be 'switch', otherwise it's 'boot'.
#   nh-options: (Optional) Any other arguments are passed directly to the
#               'nh os' command.
#
# Note: nh automatically detects the hostname from the flake configuration.
#
rebuild() {
  # Default action is 'boot'
  local action="boot"

  # If the first argument is 'switch', set the action and consume the argument.
  if [[ "$1" == "switch" ]]; then
    action="switch"
    shift # consume "switch"
  fi

  # Using an array to build the command is safer and avoids issues with word splitting.
  local -a cmd
  cmd=("nh" "os" "$action" "$HOME/nixos-config")

  # Add any extra arguments from the user at the end.
  if [[ $# -gt 0 ]]; then
    cmd+=("$@")
  fi

  # Print the command before executing
  echo "+" "${cmd[@]}"

  # Execute the command
  "${cmd[@]}"
}
