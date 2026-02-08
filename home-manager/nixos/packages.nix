{ lib, pkgs, ... }:

{
  home.packages =
    (with pkgs; [
      adw-bluetooth
      anytype
      bat
      celluloid
      chromium
      ddcutil
      devenv
      domain-check
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
      nmap
      powertop
      rsync # Required by profile-sync-daemon for browser profile syncing
      superfile
      sushi # nautilus preview
      tree
      yazi
      # Icon theme for ironbar
      papirus-icon-theme
      # Icon font for hamr
      material-symbols
    ])
    # x86_64-only packages (no ARM64 builds available)
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      pkgs.discord
      pkgs.obsidian
      pkgs.slack
      pkgs.spotify
      (import ./elecwhat.nix { inherit pkgs; })
      (import ./ticktick.nix { inherit pkgs; })
      (import ./upscayl.nix { inherit pkgs; })
    ];
}
