{ config, ... }:

{
  home.file.".config/zsh/rebuild.zsh".source = ./zsh/rebuild.zsh;
  home.file.".config/zsh/keybindings.zsh".source = ./zsh/keybindings.zsh;

  programs.zsh = {
    enable = true;
    initContent = ''
      source ${config.home.homeDirectory}/.config/zsh/rebuild.zsh
      source ${config.home.homeDirectory}/.config/zsh/keybindings.zsh
    '';
  };
}
