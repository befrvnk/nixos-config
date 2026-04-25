{ lib, pkgs, ... }:

{
  home.packages =
    (with pkgs; [
      adw-bluetooth
      anytype
      celluloid
      chromium
      ddcutil
      domain-check

      mission-center
      nautilus
      gnome-disk-utility
      opencode-desktop
      powertop
      sushi # nautilus preview
      # Icon theme for ironbar
      papirus-icon-theme

    ])
    # x86_64-only packages (no ARM64 builds available)
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      pkgs.discord
      pkgs.obsidian
      pkgs.orca-ai
      pkgs.paseo
      pkgs.slack
      pkgs.spotify
      (import ./elecwhat.nix { inherit pkgs; })
      (import ./ticktick.nix { inherit pkgs; })
      (import ./upscayl.nix { inherit pkgs; })
    ];
}
