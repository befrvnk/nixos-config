{ pkgs, ... }:
{
  system.stateVersion = 5;

  # Primary user for Homebrew and other user-specific options
  system.primaryUser = "frank";

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Let Determinate Systems installer manage Nix (don't conflict with its daemon)
  # Nix settings (flakes, substituters) are configured by Determinate instead
  nix.enable = false;

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

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };
    casks = [
      "utm"
    ];
  };

  # Touch ID for sudo (new API path)
  security.pam.services.sudo_local.touchIdAuth = true;
}
