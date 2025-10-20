{ config, pkgs, ... }:

{
  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";
  programs.bash = {
    enable = true;
    shellAliases = {
      btw = "echo i use nixos, btw";
    };
  };
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
  home.packages = with pkgs; [
    _1password-gui
    _1password-cli
    gemini-cli
  ];
}
