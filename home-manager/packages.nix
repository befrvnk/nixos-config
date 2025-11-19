{ pkgs, ... }:

{
  home.packages =
    (with pkgs; [
      anytype
      bat
      chromium
      claude-code
      discord
      eza
      fd
      fzf
      gemini-cli
      gh
      helix
      htop
      imagemagick
      jetbrains.idea-community-bin
      lf
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
