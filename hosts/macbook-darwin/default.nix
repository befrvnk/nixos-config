{ inputs, pkgs, ... }:

{
  system.stateVersion = 5;
  system.primaryUser = "frank";

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Let Determinate Systems installer manage Nix (don't conflict with its daemon)
  # Nix settings (flakes, substituters) are configured by Determinate instead
  nix.enable = false;

  # Define user for home-manager integration
  users.users.frank = {
    name = "frank";
    home = "/Users/frank";
  };

  # Home-manager integration
  home-manager = {
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
    bashInteractive
    zsh
  ];

  environment.systemPackages = with pkgs; [
    curl
    git
    vim
    wget
  ];

  # Homebrew for GUI apps not available in nixpkgs
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };
    casks = [
      "android-studio"
    ];
  };

  # macOS System Defaults
  system.defaults = {
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
  };

  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;
}
