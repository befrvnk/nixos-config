{
  config,
  osConfig,
  pkgs,
  pkgs-unstable,
  zen-browser,
  android-nixpkgs,
  ...
}:

{
  imports = [
    zen-browser.homeModules.beta
    ./stylix.nix
    (import ./zed.nix { inherit pkgs pkgs-unstable; })
    (import ./ghostty.nix {
      inherit config pkgs pkgs-unstable;
      lib = pkgs.lib;
    })
    (import ./android.nix { inherit pkgs pkgs-unstable android-nixpkgs; })
    (import ./niri/default.nix {
      inherit osConfig pkgs;
      lib = pkgs.lib;
    })
    (import ./dms.nix { inherit pkgs; })
    ./hyprlock.nix
    ./vicinae.nix
  ];

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

  home.packages = (
    with pkgs;
    [
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
    ]
  );

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
  home.activation.restartDarkman = config.lib.dag.entryAfter [ "writeBoundary" ] ''
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
