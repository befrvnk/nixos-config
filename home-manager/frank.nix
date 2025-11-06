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
  # Base stylix configuration (default to dark theme)
  stylix = {
    enable = true;
    autoEnable = true;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    image = ./wallpapers/catppuccin-mocha.jpg;

    fonts = {
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = 11;
        terminal = 11;
        desktop = 11;
      };
    };
    cursor = {
      package = pkgs.quintom-cursor-theme;
      name = "Quintom_Snow";
      size = 24;
    };
  };

  specialisation =
    let
      # Import shared theme definitions
      themes = import ./themes.nix { inherit pkgs; };

      astalTheme = colors: builtins.toJSON {
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
    in
    {
      dark.configuration = {
        stylix = {
          polarity = pkgs.lib.mkForce "dark";
          base16Scheme = pkgs.lib.mkForce themes.dark.scheme;
          image = pkgs.lib.mkForce themes.dark.wallpaper;
        };
        home.file.".config/astal-shell/theme.json".text = astalTheme config.lib.stylix.colors;
      };
      light.configuration = {
        stylix = {
          polarity = pkgs.lib.mkForce "light";
          base16Scheme = pkgs.lib.mkForce themes.light.scheme;
          image = pkgs.lib.mkForce themes.light.wallpaper;
        };
        home.file.".config/astal-shell/theme.json".text = astalTheme config.lib.stylix.colors;
      };
    };

  imports = [
    zen-browser.homeModules.beta
    (import ./zed.nix { inherit pkgs pkgs-unstable; })
    (import ./ghostty.nix { inherit config pkgs pkgs-unstable; lib = pkgs.lib; })
    (import ./android.nix { inherit pkgs pkgs-unstable android-nixpkgs; })
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
      ExecStart = "${astal-shell.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/astal-shell";
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
      home-manager
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
      astal-shell.packages.${pkgs.stdenv.hostPlatform.system}.default
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

  # Darkman configuration
  home.file.".config/darkman/config.yaml".text = ''
    lat: 48.13743
    lng: 11.57549
  '';

  # Restart darkman after home-manager activation to re-evaluate current theme
  # Only restart if we're not already being run by darkman (avoid infinite loop)
  home.activation.restartDarkman = config.lib.dag.entryAfter ["writeBoundary"] ''
    # Check if DARKMAN_RUNNING environment variable is set
    # Use parameter expansion with default to avoid "unbound variable" error
    if [ -z "''${DARKMAN_RUNNING:-}" ]; then
      $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart darkman.service || true
    fi
  '';

  # Darkman scripts for theme switching
  # Note: darkman looks for scripts in XDG_DATA_HOME/light-mode.d and XDG_DATA_HOME/dark-mode.d
  # NOT in a darkman subdirectory!
  home.file.".local/share/light-mode.d/stylix.sh" = {
    text = ''
      #!/run/current-system/sw/bin/bash
      # Set environment variable to prevent infinite restart loop
      export DARKMAN_RUNNING=1

      # Set desktop environment color scheme preference for light mode
      # This tells applications like Ghostty to use their light theme
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u)/bus"
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"

      # Find the home-manager generation with specialisations from the current system
      HM_GEN=$(/run/current-system/sw/bin/nix-store -qR /run/current-system | /run/current-system/sw/bin/grep home-manager-generation | while read gen; do
        if [ -d "$gen/specialisation" ]; then
          echo "$gen"
          break
        fi
      done)

      if [ -z "$HM_GEN" ]; then
        echo "Error: Could not find home-manager generation with specialisations" >&2
        exit 1
      fi

      "$HM_GEN/specialisation/light/activate"

      # Trigger Niri screen transition effect
      NIRI_SOCKET=$(/run/current-system/sw/bin/find /run/user/* -maxdepth 1 -name 'niri*.sock' 2>/dev/null | /run/current-system/sw/bin/head -n1)
      if [ -n "$NIRI_SOCKET" ]; then
        NIRI_SOCKET="$NIRI_SOCKET" ${pkgs.niri}/bin/niri msg action do-screen-transition
      fi
    '';
    executable = true;
  };

  home.file.".local/share/dark-mode.d/stylix.sh" = {
    text = ''
      #!/run/current-system/sw/bin/bash
      # Set environment variable to prevent infinite restart loop
      export DARKMAN_RUNNING=1

      # Set desktop environment color scheme preference for dark mode
      # This tells applications like Ghostty to use their dark theme
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u)/bus"
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"

      # Find the home-manager generation with specialisations from the current system
      HM_GEN=$(/run/current-system/sw/bin/nix-store -qR /run/current-system | /run/current-system/sw/bin/grep home-manager-generation | while read gen; do
        if [ -d "$gen/specialisation" ]; then
          echo "$gen"
          break
        fi
      done)

      if [ -z "$HM_GEN" ]; then
        echo "Error: Could not find home-manager generation with specialisations" >&2
        exit 1
      fi

      "$HM_GEN/specialisation/dark/activate"

      # Trigger Niri screen transition effect
      NIRI_SOCKET=$(/run/current-system/sw/bin/find /run/user/* -maxdepth 1 -name 'niri*.sock' 2>/dev/null | /run/current-system/sw/bin/head -n1)
      if [ -n "$NIRI_SOCKET" ]; then
        NIRI_SOCKET="$NIRI_SOCKET" ${pkgs.niri}/bin/niri msg action do-screen-transition
      fi
    '';
    executable = true;
  };

}
