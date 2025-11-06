{ config, ... }:

{
  home.file.".config/zsh/rebuild.zsh".source = ./zsh/rebuild.zsh;

  programs.zsh = {
    enable = true;
    initContent = "source ${config.home.homeDirectory}/.config/zsh/rebuild.zsh";
  };
}
