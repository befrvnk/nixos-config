{ config, pkgs, ... }:

{
  # Configure navi cheat sheet paths
  home.file.".config/navi/cheats" = {
    source = ./cheats;
    recursive = true;
  };

  # Set navi environment variables
  home.sessionVariables = {
    NAVI_PATH = "${config.home.homeDirectory}/.config/navi/cheats";
  };
}
