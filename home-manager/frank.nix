{ zen-browser, ... }:

{
  imports = [
    zen-browser.homeModules.beta
    ./stylix.nix
    ./darkman
    ./direnv.nix
    ./git.nix
    ./ssh.nix
    ./zsh.nix
    ./starship.nix
    ./zen-browser.nix
    ./packages.nix
    ./signal.nix
    ./zed.nix
    ./opencode.nix
    ./ghostty.nix
    ./android.nix
    ./niri
    ./navi
    ./ironbar
    ./dunst.nix
    ./swaylock.nix
    ./vicinae.nix
    ./media-suspend.nix
  ];

  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";

  # Enable Wayland support for Electron apps (Discord, Slack, Anytype, etc.)
  # This tells Electron to use the Ozone platform layer with Wayland flags:
  # --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true
  # Without this, Electron apps may fall back to X11 mode causing rendering issues
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };
}
