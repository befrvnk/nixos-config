{ zen-browser, ... }:

{
  imports = [
    zen-browser.homeModules.beta
    ./stylix.nix
    ./darkman.nix
    ./git.nix
    ./ssh.nix
    ./zsh.nix
    ./starship.nix
    ./zen-browser.nix
    ./packages.nix
    ./dconf.nix
    ./zed.nix
    ./ghostty.nix
    ./android.nix
    ./niri
    ./waybar
    ./dunst.nix
    ./hyprlock.nix
    ./vicinae.nix
  ];

  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";
}
