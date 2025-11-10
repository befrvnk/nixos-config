{ pkgs, ... }:

{
  home.packages = (
    with pkgs;
    [
      # _1password-cli and _1password-gui now managed by system-level programs
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
      navi
      neofetch
      starship
      tree
    ]
  );
}
