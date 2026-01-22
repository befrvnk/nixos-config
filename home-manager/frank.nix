{ inputs, ... }:

{
  imports = [
    inputs.zen-browser.homeModules.beta
    ./android
    ./atuin.nix
    ./audio-idle-inhibit
    ./battery-notifications
    ./btop.nix
    ./claude-code
    ./darkman
    ./direnv.nix
    ./dunst.nix
    ./emacs.nix
    ./gemini-cli.nix
    ./ghostty.nix
    ./git.nix
    ./hamr.nix
    ./intellij
    ./ironbar
    ./jujutsu.nix
    ./lazygit.nix
    ./navi
    ./nil.nix
    ./niri
    ./nushell.nix
    ./obsidian.nix
    ./packages.nix
    ./polkit-agent.nix
    ./profile-sync-daemon.nix
    ./signal.nix
    ./spotify-suspend
    ./ssh.nix
    ./starship.nix
    ./stylix.nix
    ./swaylock.nix
    ./udiskie.nix
    ./vicinae.nix
    ./zed.nix
    ./zen-browser
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

  # Enable SwayOSD for volume/brightness on-screen display
  services.swayosd.enable = true;
}
