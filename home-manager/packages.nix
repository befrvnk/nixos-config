{ pkgs, ... }:

{
  home.packages =
    (with pkgs; [
      adw-bluetooth
      anytype
      bat
      chromium
      ddcutil
      devenv
      discord
      eza
      fd
      fzf
      gh
      helix
      htop
      imagemagick
      lf
      mission-center
      nautilus
      gnome-disk-utility
      navi
      neofetch
      nh
      obsidian
      powertop
      slack
      spotify
      superfile
      sushi # nautilus preview
      tree
      yazi
      # Icon theme for ironbar
      papirus-icon-theme
    ])
    ++ [
      (import ./elecwhat.nix { inherit pkgs; })
      (import ./ticktick.nix { inherit pkgs; })
      (import ./upscayl.nix { inherit pkgs; })
    ];
}
