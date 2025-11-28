{ inputs, ... }:

{
  imports = [
    inputs.zen-browser.homeModules.beta
    ./android.nix
    ./atuin.nix
    ./battery-notifications
    ./claude-code
    ./darkman
    ./direnv.nix
    ./dunst.nix
    ./gemini-cli.nix
    ./ghostty.nix
    ./git.nix
    ./ironbar
    ./media-suspend
    ./navi
    ./niri
    ./opencode
    ./packages.nix
    ./signal.nix
    ./ssh.nix
    ./starship.nix
    ./stylix.nix
    ./swaylock.nix
    ./vicinae.nix
    ./zed.nix
    ./zen-browser.nix
    ./zsh.nix
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
