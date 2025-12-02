{ pkgs, ... }:

{
  home.packages =
    (with pkgs; [
      anytype
      bat
      btop
      chromium
      devenv
      discord
      eza
      fd
      fzf
      gh
      helix
      htop
      imagemagick
      jetbrains.idea-community-bin
      lf
      mission-center
      nautilus
      navi
      neofetch
      nh
      powertop
      slack
      spotify
      superfile
      sushi # nautilus preview
      ticktick
      tree
      yazi
      zapzap
      # Icon theme for ironbar
      papirus-icon-theme
    ])
    ++ [
      (import ./upscayl.nix { inherit pkgs; })
    ];
}
