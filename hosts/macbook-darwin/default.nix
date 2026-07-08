{
  inputs,
  lib,
  pkgs,
  hostConfig,
  ...
}:

{
  system = {
    stateVersion = 5;
    inherit (hostConfig) primaryUser;

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
        "com.apple.symbolichotkeys" = {
          AppleSymbolicHotKeys = {
            # Disable Spotlight's Cmd+Space bindings so skhd can use it for Vicinae.
            "64".enabled = false; # Show Spotlight search
            "65".enabled = false; # Show Finder search window
          };
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

  # nix-darwin's current manual builder still passes removed nixos-render-docs
  # *-toc-depth flags in some build paths. Avoid pulling the broken HTML manual
  # and the uninstaller's nested manual build into the Darwin closure.
  documentation.doc.enable = false;
  system.tools.darwin-uninstaller.enable = false;

  # Define user for home-manager integration
  # knownUsers + uid required for nix-darwin to manage shell via chsh
  users.knownUsers = [ hostConfig.primaryUser ];
  users.users.${hostConfig.primaryUser} = {
    name = hostConfig.primaryUser;
    home = hostConfig.homeDirectory;
    shell = pkgs.nushell;
    uid = 501;
  };

  # Home-manager integration
  home-manager = {
    backupFileExtension = "backup";
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${hostConfig.primaryUser} = ../../home-manager/darwin/frank.nix;
    extraSpecialArgs = {
      inherit inputs hostConfig;
    };
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
      # Keep rebuilds idempotent: install missing Brewfile entries, but don't
      # auto-update/upgrade/zap every cask during nix-darwin activation.
      # Homebrew cask upgrades can invoke repeated sudo prompts or hang when
      # apps are running. Zen Browser is updated by a user launchd agent below
      # because it does not expose an in-app updater.
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
    taps = [
      {
        name = "BarutSRB/tap";
        trusted = true;
      }
      {
        name = "darrylmorley/whatcable";
        trusted = true;
      }
      {
        name = "muxy-app/tap";
        trusted = true;
      }
    ];
    casks =
      let
        greedyCasks =
          map
            (name: {
              inherit name;
              greedy = true;
            })
            [
              "1password"
              "caffeine"
              "ghostty"
              "github-copilot-app"
              "jetbrains-toolbox"
              "miro"
              "muxy"
              "notion"
              "opencode-desktop"
              "paseo"
              "raycast"
              "signal"
              "spotify"
              "whatsapp"
              "whatcable"
              "zed"
              "zen"
            ];
        selfUpdatingCasks = [
          # These apps self-update; forcing a Homebrew greedy upgrade can fail
          # activation when the app is running or has already partially updated.
          "claude"
          "lunar"
          "slack"
        ];
      in
      selfUpdatingCasks ++ greedyCasks;
  };

  # Expose Nix-managed binaries to GUI apps (Dock/Spotlight launched apps only
  # get launchd's minimal PATH and can't find tools like git, gh, etc.)
  # Runs at login and sets PATH for the entire user launchd session.
  launchd.user.agents = {
    "nix-path".serviceConfig = {
      Label = "nix.path";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/launchctl setenv PATH /etc/profiles/per-user/${hostConfig.primaryUser}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      ];
      RunAtLoad = true;
    };

    "zen-browser-homebrew-update".serviceConfig = {
      Label = "zen.browser.homebrew.update";
      ProgramArguments = [
        "/bin/sh"
        "-lc"
        ''
          if [ ! -x /opt/homebrew/bin/brew ]; then
            exit 0
          fi

          if /usr/bin/pgrep -f '/Applications/Zen\.app/Contents/MacOS/zen|/Zen\.app/Contents/MacOS/zen' >/dev/null; then
            echo "Zen Browser is running; skipping Homebrew update"
            exit 0
          fi

          /opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade --cask --greedy zen
        ''
      ];
      RunAtLoad = true;
      StandardErrorPath = "${hostConfig.homeDirectory}/Library/Logs/zen-browser-homebrew-update.log";
      StandardOutPath = "${hostConfig.homeDirectory}/Library/Logs/zen-browser-homebrew-update.log";
      StartCalendarInterval = [
        {
          Hour = 10;
          Minute = 0;
        }
      ];
    };
  };

  # Supacode's GitHub integration currently expects the GitHub CLI in the
  # Homebrew prefix. gh is installed by Home Manager via nixpkgs, so expose a
  # stable compatibility symlink without installing gh through Homebrew.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    gh_link="/opt/homebrew/bin/gh"
    gh_target="/etc/profiles/per-user/${hostConfig.primaryUser}/bin/gh"

    if [ -L "$gh_link" ]; then
      current_target="$(readlink "$gh_link")"
      if [ "$current_target" != "$gh_target" ]; then
        case "$current_target" in
          /nix/store/*|/etc/profiles/per-user/*)
            echo "updating $gh_link -> $gh_target"
            ln -sfn "$gh_target" "$gh_link"
            ;;
          *)
            echo "leaving existing $gh_link -> $current_target"
            ;;
        esac
      fi
    elif [ -e "$gh_link" ]; then
      echo "warning: $gh_link exists and is not a symlink; leaving it untouched"
    else
      echo "linking $gh_link -> $gh_target"
      mkdir -p "$(dirname "$gh_link")"
      ln -s "$gh_target" "$gh_link"
    fi

  '';

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
