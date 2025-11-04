{
  config,
  osConfig,
  pkgs,
  pkgs-unstable,
  zen-browser,
  android-nixpkgs,
  astal-shell,
  ...
}:

{
  imports = [
    zen-browser.homeModules.beta
    (import ./zed.nix { inherit pkgs pkgs-unstable; })
    (import ./android.nix { inherit pkgs pkgs-unstable android-nixpkgs; })
    ./stylix.nix
    (import ./niri/default.nix {
      inherit osConfig pkgs;
      lib = pkgs.lib;
    })
    # (import ./waybar/default.nix { inherit pkgs osConfig nix-colors; })  # Replaced with astal-shell
    ./hyprlock.nix
    ./vicinae.nix
  ];

  # Create systemd service to run astal-shell
  systemd.user.services.astal-shell = {
    Unit = {
      Description = "Astal Shell - Desktop shell for Wayland";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${astal-shell.packages.${pkgs.system}.default}/bin/astal-shell";
      Restart = "on-failure";
      RestartSec = "3s";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";

  home.file.".config/zsh/rebuild.zsh".source = ./zsh/rebuild.zsh;

  # Configure astal-shell with Stylix colors
  home.file.".config/astal-shell/theme.json".text =
    let
      colors = config.lib.stylix.colors;
    in
    builtins.toJSON {
      # Base16 colors from Stylix
      background = "#${colors.base00}";
      surface0 = "#${colors.base01}";
      surface1 = "#${colors.base02}";
      surface2 = "#${colors.base03}";
      overlay0 = "#${colors.base03}";
      overlay1 = "#${colors.base04}";
      overlay2 = "#${colors.base04}";
      text = "#${colors.base05}";
      subtext0 = "#${colors.base04}";
      subtext1 = "#${colors.base05}";

      # Accent colors from base16
      blue = "#${colors.base0D}";
      lavender = "#${colors.base07}";
      sapphire = "#${colors.base0C}";
      sky = "#${colors.base0C}";
      teal = "#${colors.base0C}";
      green = "#${colors.base0B}";
      yellow = "#${colors.base0A}";
      peach = "#${colors.base09}";
      maroon = "#${colors.base08}";
      red = "#${colors.base08}";
      mauve = "#${colors.base0E}";
      pink = "#${colors.base0E}";
      flamingo = "#${colors.base0F}";
      rosewater = "#${colors.base06}";

      # UI specific colors
      primary = "#${colors.base0D}";
      error = "#${colors.base08}";
      success = "#${colors.base0B}";
      warning = "#${colors.base0A}";

      # Opacity
      opacity = 0.95;

      # Typography
      font = {
        family = "Inter";
        size = 13;
        weight = 400;
      };

      # Spacing
      spacing = 8;

      # Border radius
      radius = 12;
    };

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
  home.packages =
    (with pkgs; [
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
      radeontop # AMD GPU monitoring
      brightnessctl # Brightness control
      mako # Notification daemon for Wayland
      libnotify # Notification library
    ])
    ++ [
      # Astal-shell from flake input
      astal-shell.packages.${pkgs.system}.default
    ];

  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      sources = [
        [
          "xkb"
          "us-umlauts"
        ]
      ];
    };
  };
}
