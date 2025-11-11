{ config, ... }:

{
  programs.navi = {
    enable = true;
    enableZshIntegration = true;
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
