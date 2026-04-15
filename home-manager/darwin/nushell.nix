# Darwin-specific Nushell configuration
#
# Shared config (keybindings, navi, wt, launch, carapace) is in shared/nushell.nix.
# This file handles Nix PATH setup on Darwin and provides an opt-in helper for
# populating GITHUB_TOKEN when a command actually needs it.

_:

{
  programs.nushell = {
    extraConfig = ''
      def --env ensure-github-token [] {
        if (($env.GITHUB_TOKEN? | default "") | is-not-empty) {
          return
        }

        let result = (do { gh auth token } | complete)
        if $result.exit_code == 0 {
          let token = ($result.stdout | str trim)
          if ($token | is-not-empty) {
            $env.GITHUB_TOKEN = $token
          }
        }
      }
    '';

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
    '';
  };
}
