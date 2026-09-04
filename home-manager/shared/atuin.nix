{ pkgs, ... }: {
  programs.atuin = {
    enable = true;
    enableNushellIntegration = true;
    # Work around Nushell warning `nu::shell::shared_keybindings_name` caused by
    # Atuin generating duplicate `name: atuin` keybindings for both Ctrl-R and Up Arrow.
    # Fixed upstream in Atuin PR #3975 by renaming the Up Arrow binding to `atuin_up_arrow`.
    package = pkgs.symlinkJoin {
      name = "atuin-${pkgs.atuin.version}";
      paths = [
        (pkgs.writeShellScriptBin "atuin" ''
          if [ "$1" = "init" ] && [ "$2" = "nu" ]; then
            ${pkgs.atuin}/bin/atuin "$@" | ${pkgs.gawk}/bin/awk '/name: atuin/ { count++; if (count > 1) sub("name: atuin", "name: atuin_up_arrow") } { print }'
          else
            exec ${pkgs.atuin}/bin/atuin "$@"
          fi
        '')
        pkgs.atuin
      ];
      meta.mainProgram = "atuin";
    };
    settings = {
      ai.enabled = true;
    };
  };
}
