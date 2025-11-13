{ pkgs, ... }:

{
  home.packages = (
    with pkgs;
    [
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
      jetbrains.idea-community-bin
      lf
      navi
      neofetch
      signal-desktop
      slack
      spotify
      ticktick
      tree
      zapzap
      # Icon theme for ironbar
      papirus-icon-theme
    ]
  );
}
