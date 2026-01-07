{ config, ... }:

{
  # Navi cheatsheet tool
  # Nushell widget integration is in nushell.nix (Ctrl+G)
  # since home-manager navi module lacks enableNushellIntegration
  programs.navi = {
    enable = true;
    settings = {
      cheats = {
        paths = [
          "${config.home.homeDirectory}/.config/navi/cheats"
        ];
      };
    };
  };

  # Configure navi cheat sheet paths
  home.file.".config/navi/cheats" = {
    source = ./cheats;
    recursive = true;
  };
}
