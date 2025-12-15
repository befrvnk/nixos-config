{ pkgs, ... }:

{
  home.packages =
    (with pkgs; [
      adw-bluetooth
      anytype
      bat
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
      lazygit
      lf
      mission-center
      nautilus
      navi
      neofetch
      nh
      obsidian
      powertop
      slack
      solaar
      spotify
      superfile
      sushi # nautilus preview
      tree
      yazi
      zapzap
      # Icon theme for ironbar
      papirus-icon-theme
    ])
    ++ [
      (import ./ticktick.nix { inherit pkgs; })
      (import ./upscayl.nix { inherit pkgs; })
    ];
}
