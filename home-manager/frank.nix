{ config, pkgs, pkgs-unstable, zen-browser, inputs, ... }:

{
  imports = [
    zen-browser.homeModules.beta
    (import ./zed.nix { inherit pkgs pkgs-unstable; })
  ];

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
  programs.zen-browser.enable = true;
  home.packages = with pkgs; [
    pkgs-unstable._1password-cli
    pkgs-unstable._1password-gui
    pkgs-unstable.anytype
    pkgs-unstable.discord
    pkgs-unstable.gemini-cli
    pkgs-unstable.ghostty
    pkgs-unstable.helix
    pkgs-unstable.signal-desktop
    pkgs-unstable.slack
    pkgs-unstable.spotify
    pkgs-unstable.zapzap
    bat
    eza
    fd
    fzf
    gh
    htop
    lf
    neofetch
    starship
    tree
  ];
}
