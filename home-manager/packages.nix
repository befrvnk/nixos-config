{ pkgs, pkgs-unstable, ... }:

{
  home.packages = (
    with pkgs;
    [
      pkgs-unstable._1password-cli
      pkgs-unstable._1password-gui
      pkgs-unstable.anytype
      pkgs-unstable.claude-code
      pkgs-unstable.discord
      pkgs-unstable.gemini-cli
      pkgs-unstable.helix
      pkgs-unstable.jetbrains.idea-community-bin
      pkgs-unstable.signal-desktop
      pkgs-unstable.slack
      pkgs-unstable.spotify
      pkgs-unstable.ticktick
      pkgs-unstable.zapzap
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
