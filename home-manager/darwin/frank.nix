# Darwin-specific home-manager configuration
#
# This imports cross-platform shared modules plus darwin-specific configs.
# Linux-specific modules (Wayland, systemd services, etc.) are excluded.
#
# Key differences from NixOS:
# - No Stylix theming (macOS uses system appearance)
# - No Wayland/niri compositor
# - No Linux-specific services (ironbar, darkman, battery-notifications, etc.)
# - No systemd user services

{ inputs, ... }:

{
  imports = [
    # Shared modules (cross-platform)
    ../shared

    # Darwin-specific modules
    inputs.zen-browser.homeModules.beta
    ./ghostty.nix
    ./zed.nix
    ./nushell.nix
    ./packages.nix
    ./zellij.nix
    ./zen-browser.nix
  ];

  home = {
    username = "frank";
    homeDirectory = "/Users/frank";
    stateVersion = "25.05";
  };

}
