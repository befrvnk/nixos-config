{
  lib,
  nixos-raspberrypi,
  pkgs,
  ...
}:

let
  openchamberVersion = "1.19.0";
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

  # Trust the Framework's signing key so plain remote deploys work
  # (nixos-rebuild --target-host). See docs/hermi-raspberry-pi-setup.md.
  nix.settings."trusted-public-keys" = [
    "hermi-signing:Me8nPXnFEi62cG/h0k4ZjJmnWFT3kzsbWTWpW+YPoHI="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
  ];

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

  system.activationScripts."openchamber-setup" = lib.stringAfter [ "users" "groups" ] ''
    mkdir -p /var/lib/openchamber/app
    chown openchamber:openchamber /var/lib/openchamber /var/lib/openchamber/app
    chmod 0750 /var/lib/openchamber

    installed_version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' /var/lib/openchamber/app/node_modules/@openchamber/web/package.json 2>/dev/null | head -n1)"
    if [ "$installed_version" != "${openchamberVersion}" ]; then
      echo "Installing OpenChamber ${openchamberVersion} (downloads from npm)..."
      rm -rf /var/lib/openchamber/app/node_modules
      # npm lifecycle scripts (node-pty etc.) need 'node', 'sh' and common
      # utils, which are absent from the activation environment's minimal PATH.
      export PATH="${pkgs.nodejs_22}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:${pkgs.findutils}/bin":$PATH
      ${pkgs.nodejs_22}/bin/npm install --omit=dev --no-audit --no-fund \
        --prefix /var/lib/openchamber/app "@openchamber/web@${openchamberVersion}"
      chown -R openchamber:openchamber /var/lib/openchamber/app
    fi
  '';

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
          pkgs.curl
          pkgs.git
          pkgs.neovim
          pkgs.opencode
        ]
      );
    };
    serviceConfig = {
      User = "openchamber";
      Group = "openchamber";
      WorkingDirectory = "/var/lib/openchamber";
      EnvironmentFile = "-/var/lib/openchamber/env";
      ExecStartPre = "${pkgs.gnugrep}/bin/grep -q '^OPENCHAMBER_UI_PASSWORD=.' /var/lib/openchamber/env";
      ExecStart = "${pkgs.nodejs_22}/bin/node /var/lib/openchamber/app/node_modules/@openchamber/web/bin/cli.js serve --lan --port 3000 --foreground";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
  };

  environment.systemPackages = with pkgs; [
    bash
    curl
    git
    neovim
    nodejs_22
    opencode
  ];

  system.stateVersion = "25.05";
}
