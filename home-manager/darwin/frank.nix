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
    ../shared/atuin.nix
    ../shared/btop.nix
    ../shared/claude-code
    ../shared/direnv.nix
    ../shared/git.nix
    ../shared/jujutsu.nix
    ../shared/lazygit.nix
    ../shared/navi
    ../shared/nil.nix
    ../shared/ssh.nix
    ../shared/starship.nix
    ../shared/worktrunk.nix
    ../shared/zed.nix

    # Darwin-specific modules
    inputs.zen-browser.homeModules.beta
    ./ghostty.nix
    ./nushell.nix
    ./packages.nix
    ./zen-browser.nix
  ];

  home.username = "frank";
  home.homeDirectory = "/Users/frank";
  home.stateVersion = "25.05";

}
