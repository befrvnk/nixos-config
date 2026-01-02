{ config, ... }:

{
  home.file.".config/zsh/keybindings.zsh".source = ./keybindings.zsh;

  programs.zsh = {
    enable = true;
    initContent = ''
      source ${config.home.homeDirectory}/.config/zsh/keybindings.zsh
    '';
    shellAliases = {
      # Firewall log viewing
      firewall-log = "journalctl -k | grep 'refused'";
      firewall-log-live = "sudo dmesg --follow | grep 'refused'";
    };
  };
}
