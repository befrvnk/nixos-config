{ zen-browser, ... }:

{
  imports = [
    zen-browser.homeModules.beta
    ./stylix.nix
    ./darkman
    ./direnv.nix
    ./git.nix
    ./ssh.nix
    ./zsh.nix
    ./starship.nix
    ./zen-browser.nix
    ./packages.nix
    ./zed.nix
    ./opencode.nix
    ./ghostty.nix
    ./android.nix
    ./niri
    ./navi
    ./ironbar
    ./dunst.nix
    ./swaylock.nix
    ./vicinae.nix
  ];

  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";
}
