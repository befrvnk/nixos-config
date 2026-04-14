{ inputs, pkgs, ... }:

{
  system = {
    stateVersion = 5;
    primaryUser = "frank";

    # macOS System Defaults
    defaults = {
      dock = {
        autohide = true;
        show-recents = false;
        tilesize = 48;
        mru-spaces = false;
      };
      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        ShowStatusBar = true;
        FXEnableExtensionChangeWarning = false;
        _FXShowPosixPathInTitle = true;
      };
      NSGlobalDomain = {
        AppleKeyboardUIMode = 3; # Full keyboard access
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        ApplePressAndHoldEnabled = false;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
      };
      trackpad = {
        Clicking = true;
        TrackpadRightClick = true;
      };

      # Disable "Search man Page Index in Terminal" service shortcut (Cmd+Shift+A)
      # Conflicts with JetBrains IDEs "Find Action" shortcut
      # Requires logout/login to take effect
      CustomUserPreferences = {
        # Enable Cmd+Ctrl+drag to move windows from anywhere (not just title bar)
        # Requires logout/login to take effect
        "NSGlobalDomain" = {
          NSWindowShouldDragOnGesture = true;
        };
        "pbs" = {
          NSServicesStatus = {
            "com.apple.Terminal - Search man Page Index in Terminal - searchManPages" = {
              "enabled_context_menu" = false;
              "enabled_services_menu" = false;
              "presentation_modes" = {
                "ContextMenu" = false;
                "ServicesMenu" = false;
              };
            };
          };
        };
      };
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-darwin";
  };

  # Let Determinate Systems installer manage Nix (don't conflict with its daemon)
  # Nix settings (flakes, substituters) are configured by Determinate instead
  nix.enable = false;

  # Define user for home-manager integration
  # knownUsers + uid required for nix-darwin to manage shell via chsh
  users.knownUsers = [ "frank" ];
  users.users.frank = {
    name = "frank";
    home = "/Users/frank";
    shell = pkgs.nushell;
    uid = 501;
  };

  # Home-manager integration
  home-manager = {
    backupFileExtension = "backup";
    useGlobalPkgs = true;
    useUserPackages = true;
    users.frank = ../../home-manager/darwin/frank.nix;
    extraSpecialArgs = { inherit inputs; };
  };

  # Shell configuration
  programs.zsh = {
    enable = true;
    shellInit = ''
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
    '';
  };

  environment.shells = with pkgs; [
    nushell
    zsh
  ];

  environment.systemPackages = with pkgs; [
    curl
    git
    vim
    wget
  ];

  # Homebrew for GUI apps that either are missing from nixpkgs on darwin
  # or need native macOS install/update behavior (for example Raycast).
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };
    taps = [
      "BarutSRB/tap"
    ];
    casks =
      map
        (name: {
          inherit name;
          greedy = true;
        })
        [
          "1password"
          "caffeine"
          "ghostty"
          "jetbrains-toolbox"
          "lunar"
          "miro"
          "notion"
          "opencode-desktop"
          "raycast"
          "signal"
          "slack"
          "spotify"
          "whatsapp"
          "zed"
          "zen"
        ];
  };

  # Expose Nix-managed binaries to GUI apps (Dock/Spotlight launched apps only
  # get launchd's minimal PATH and can't find tools like git, gh, etc.)
  # Runs at login and sets PATH for the entire user launchd session.
  launchd.user.agents."nix-path" = {
    serviceConfig = {
      Label = "nix.path";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/launchctl setenv PATH /etc/profiles/per-user/frank/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      ];
      RunAtLoad = true;
    };
  };

  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # Increase file descriptor limit for Nix operations
  # Fixes "Too many open files" errors during flake updates
  launchd.daemons.limit-maxfiles = {
    serviceConfig = {
      Label = "limit.maxfiles";
      ProgramArguments = [
        "/bin/launchctl"
        "limit"
        "maxfiles"
        "524288"
        "524288"
      ];
      RunAtLoad = true;
    };
  };

}
