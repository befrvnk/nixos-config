{ config, pkgs, ... }:

{
  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";

  home.file.".config/zsh/rebuild.zsh".source = ./zsh/rebuild.zsh;

  programs.git = {
    enable = true;
    userName = "Frank Hermann";
    userEmail = "hermann.frank@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
    };
  };
  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host *
        IdentityAgent ~/.1password/agent.sock
    '';
  };
  programs.zsh = {
    enable = true;
    initContent = "source ${config.home.homeDirectory}/.config/zsh/rebuild.zsh";
  };
  programs.starship = {
    enable = true;
  };
  home.packages = with pkgs; [
    _1password-cli
    _1password-gui
    anytype
    bat
    eza
    fd
    fzf
    gemini-cli
    gh
    helix
    htop
    lf
    neofetch
    starship
    tree
  ];
}
