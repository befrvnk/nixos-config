{
  lib,
  nixos-raspberrypi,
  pkgs,
  ...
}:

let
  openchamber = pkgs.callPackage ../../pkgs/openchamber/package.nix { };
in
{
  imports = [
    nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    nixos-raspberrypi.nixosModules.sd-image
  ];

  # The sd-image profile enables ZFS support via profiles/base.nix, but hermi is
  # ext4-only. Disable it to silence the boot.zfs.forceImportRoot eval warning and
  # avoid pulling the zfs kernel module, services, and package into the image.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  networking = {
    hostName = "hermi";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        3000
      ];
    };
  };

  nix = {
    # Trust the Framework's signing key so plain remote deploys work
    # (nh os switch --target-host). See docs/hermi-raspberry-pi-setup.md.
    settings."trusted-public-keys" = [
      "hermi-signing:Me8nPXnFEi62cG/h0k4ZjJmnWFT3kzsbWTWpW+YPoHI="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];

    # The SD card is small and remote deploys add store paths on every switch.
    # Persistent timers catch up after the Pi has been offline.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
      persistent = true;
    };
    optimise.automatic = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      # Accept TERM from the Framework (SetEnv in home-manager/shared/ssh.nix)
      # so Ghostty's xterm-ghostty value never reaches the Pi's ncurses.
      AcceptEnv = [ "TERM" ];
    };
  };

  users = {
    users = {
      frank = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINORbEqnNt1PuKmKZn0BW/lmbAvy8L6+q1V9PP9W4vQg"
        ];
      };

      # Headless OpenChamber server for mobile and remote agent work.
      openchamber = {
        isSystemUser = true;
        group = "openchamber";
        home = "/var/lib/openchamber";
        createHome = true;
      };
    };
    groups.openchamber = { };
  };

  # The image has no password hash for frank. SSH public-key authentication is
  # therefore the initial administrative credential; require a password only
  # after one has been configured on the Pi.
  security.sudo.wheelNeedsPassword = false;

  systemd.services.openchamber = {
    description = "OpenChamber headless server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      HOME = "/var/lib/openchamber";
      PATH = lib.mkForce (
        lib.makeBinPath [
          pkgs.bash
          pkgs.coreutils
          pkgs.curl
          pkgs.git
          pkgs.gnugrep
          pkgs.gnused
          pkgs.neovim
          pkgs.opencode
        ]
      );
    };
    serviceConfig = {
      User = "openchamber";
      Group = "openchamber";
      WorkingDirectory = "/var/lib/openchamber";
      StateDirectory = "openchamber";
      StateDirectoryMode = "0750";
      EnvironmentFile = "-/var/lib/openchamber/env";
      ExecStartPre = "${pkgs.gnugrep}/bin/grep -q '^OPENCHAMBER_UI_PASSWORD=.' /var/lib/openchamber/env";
      ExecStart = "${openchamber}/bin/openchamber-web serve --lan --port 3000 --foreground";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";

      # The server is reachable from the LAN and runs agent sessions; keep its
      # system view read-only except for its own state directory.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/openchamber" ];
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictSUIDSGID = true;
      LockPersonality = true;
    };
  };

  environment.systemPackages = [
    openchamber
  ]
  ++ (with pkgs; [
    bash
    curl
    git
    neovim
    nodejs_22
    opencode
  ]);

  system.stateVersion = "25.05";
}
