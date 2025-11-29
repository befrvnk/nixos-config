{ config, ... }:

{
  home.file.".config/zsh/keybindings.zsh".source = ./keybindings.zsh;

  programs.zsh = {
    enable = true;
    initContent = ''
      source ${config.home.homeDirectory}/.config/zsh/keybindings.zsh
    '';
  };
}
