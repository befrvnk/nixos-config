# Custom rebuild function for NixOS
#
# This function wraps 'nixos-rebuild' to provide a convenient way to
# build and switch configurations while managing boot menu entries.
#
# Usage:
#   rebuild [switch] [profile-name] [nixos-rebuild-options]
#
# Arguments:
#   switch: (Optional) If provided, the action will be 'switch', otherwise it's 'build'.
#   profile-name: (Optional) A name for the NixOS profile. If provided, it creates a new
#                 boot menu entry with this name. This is useful for testing different
#                 configurations.
#   nixos-rebuild-options: (Optional) Any other arguments are passed directly to the
#                          'nixos-rebuild' command (e.g., --show-trace).
#
rebuild() {
  # Default action is 'boot'
  local action="boot"
  local profile_args=()

  # If the first argument is 'switch', set the action and consume the argument.
  if [[ "$1" == "switch" ]]; then
    action="switch"
    shift # consume "switch"
  fi

  # If the next argument is a profile name (and not a flag), set the --profile-name argument.
  # This allows creating named profiles for the boot menu.
  if [[ -n "$1" && "$1" != --* ]]; then
    profile_args=("--profile-name" "$1")
    shift # consume profile name
  fi

  # Using an array to build the command is safer and avoids issues with word splitting.
  local -a cmd
  cmd=("sudo" "nixos-rebuild" "$action")

  # Add profile name arguments if present
  if [[ ${#profile_args[@]} -gt 0 ]]; then
    cmd+=("${profile_args[@]}")
  fi

  # Add remaining arguments
  cmd+=(--flake "$HOME/nixos-config#$(hostname)")
  
  # Add any extra arguments from the user at the end.
  if [[ $# -gt 0 ]]; then
    cmd+=("$@")
  fi

  # Print the command before executing
  echo "+" "${cmd[@]}"

  # Execute the command
  "${cmd[@]}"
}
