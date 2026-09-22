{
  lib,
  pkgs,
  ...
}:

{
  home.packages =
    (with pkgs; [
      adw-bluetooth
      anytype
      celluloid
      chromium
      ddcutil
      domain-check
      github-copilot-app
      gnome-disk-utility
      mission-center
      nautilus
      openchamber
      # Icon theme for ironbar
      papirus-icon-theme
      powertop
      sushi # nautilus preview
      vscode
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
