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

    # NixOS-specific modules
    inputs.zen-browser.homeModules.beta
    ./android
    ./audio-idle-inhibit
    ./audio-keep-alive
    ./battery-notifications
    ./darkman
    ./dunst.nix
    ./emacs.nix
    ./gemini-cli.nix
    ./ghostty.nix
    ./hamr.nix
    ./intellij
    ./ironbar
    ./niri
    ./nushell.nix
    ./obsidian.nix
    ./packages.nix
    ./polkit-agent.nix
    ./profile-sync-daemon.nix
    ./signal.nix
    ./spotify-suspend
    ./stylix.nix
    ./swaylock.nix
    ./udiskie.nix
    ./vicinae.nix
    ./zen-browser
  ];

  home = {
    username = "frank";
    homeDirectory = "/home/frank";
    stateVersion = "25.05";

    # Enable Wayland support for Electron apps (Discord, Slack, Anytype, etc.)
    # This tells Electron to use the Ozone platform layer with Wayland flags:
    # --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true
    # Without this, Electron apps may fall back to X11 mode causing rendering issues
    sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };

  # Enable SwayOSD for volume/brightness on-screen display
  services.swayosd.enable = true;
}
