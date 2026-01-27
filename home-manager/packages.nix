{ pkgs, ... }:

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
      nmap
      obsidian
      powertop
      rsync # Required by profile-sync-daemon for browser profile syncing
      slack
      spotify
      superfile
      sushi # nautilus preview
      tree
      yazi
      # Icon theme for ironbar
      papirus-icon-theme
      # Icon font for hamr
      material-symbols
    ])
    ++ [
      (import ./elecwhat.nix { inherit pkgs; })
      (import ./ticktick.nix { inherit pkgs; })
      (import ./upscayl.nix { inherit pkgs; })
    ];
}
