{ config, osConfig, pkgs, pkgs-unstable, zen-browser, android-nixpkgs, nix-colors, astal-shell, ... }:

{
  imports = [
    zen-browser.homeModules.beta
    (import ./zed.nix { inherit pkgs pkgs-unstable; })
    (import ./android.nix { inherit pkgs pkgs-unstable android-nixpkgs; })
    ./stylix.nix
    (import ./niri/default.nix { inherit osConfig pkgs nix-colors; lib = pkgs.lib; })
    # (import ./waybar/default.nix { inherit pkgs osConfig nix-colors; })  # Replaced with astal-shell
    ./hyprlock.nix
    ./vicinae.nix
  ];

  # Create systemd service to run astal-shell
  systemd.user.services.astal-shell = {
    Unit = {
      Description = "Astal Shell - Desktop shell for Wayland";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };

    Service = {
      Type = "simple";
      ExecStart = "${astal-shell.packages.${pkgs.system}.default}/bin/astal-shell";
      Restart = "on-failure";
      RestartSec = "3s";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";


  home.file.".config/zsh/rebuild.zsh".source = ./zsh/rebuild.zsh;


  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Frank Hermann";
        email = "hermann.frank@gmail.com";
      };
      init.defaultBranch = "main";
    };
  };
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      identityAgent = "~/.1password/agent.sock";
    };
  };
  programs.zsh = {
    enable = true;
    initContent = "source ${config.home.homeDirectory}/.config/zsh/rebuild.zsh";
  };
  programs.starship = {
    enable = true;
  };
  programs.zen-browser.enable = true;
  home.packages = (with pkgs; [
    pkgs-unstable._1password-cli
    pkgs-unstable._1password-gui
    pkgs-unstable.anytype
    pkgs-unstable.claude-code
    pkgs-unstable.discord
    pkgs-unstable.gemini-cli
    pkgs-unstable.ghostty
    pkgs-unstable.helix
    pkgs-unstable.jetbrains.idea-community-bin
    pkgs-unstable.signal-desktop
    pkgs-unstable.slack
    pkgs-unstable.spotify
    pkgs-unstable.ticktick
    pkgs-unstable.zapzap
    bat
    eza
    fd
    fzf
    gh
    htop
    lf
    neofetch
    starship
    tree
    # AGS/Astal dependencies
    radeontop      # AMD GPU monitoring
    brightnessctl  # Brightness control
    mako           # Notification daemon for Wayland
    libnotify      # Notification library
  ]) ++ [
    # Astal-shell from flake input
    astal-shell.packages.${pkgs.system}.default
  ];

  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      sources = [ ["xkb" "us-umlauts"] ];
    };
  };
}
