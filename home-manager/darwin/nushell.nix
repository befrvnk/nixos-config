# Darwin-specific Nushell configuration
#
# Shared config (keybindings, navi, wt, launch, carapace) is in shared/nushell.nix.
# This file handles Nix PATH setup and GITHUB_TOKEN for Darwin.

_:

{
  programs.nushell = {
    # Ensure Nix paths are in PATH for terminals that don't inherit the full environment
    # (e.g. Android Studio's embedded terminal via JetBrains Toolbox)
    # Nushell doesn't source /etc/zshenv where nix-darwin normally sets these up
    extraEnv = ''
      let nix_paths = [
        $"($env.HOME)/.nix-profile/bin"
        "/etc/profiles/per-user/frank/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
      ]
      let missing = ($nix_paths | where {|p| ($p | path exists) and $p not-in $env.PATH})
      if ($missing | is-not-empty) {
        $env.PATH = ($env.PATH | prepend $missing)
      }

      # Set GITHUB_TOKEN for higher API rate limits (used by Nix flake updates)
      $env.GITHUB_TOKEN = (do { gh auth token } | complete | get stdout | str trim)
    '';
  };
}
