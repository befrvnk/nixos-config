{ pkgs, ... }:

{
  home.packages = (
    with pkgs;
    [
      _1password-cli
      _1password-gui
      anytype
      chromium
      claude-code
      discord
      gemini-cli
      helix
      jetbrains.idea-community-bin
      signal-desktop
      slack
      spotify
      ticktick
      zapzap
      bat
      eza
      fd
      fzf
      gh
      home-manager
      htop
      lf
      neofetch
      starship
      tree
    ]
  );
}
