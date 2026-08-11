{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
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
        9119
      ];
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.frank = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINORbEqnNt1PuKmKZn0BW/lmbAvy8L6+q1V9PP9W4vQg"
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  services.hermes-agent = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
    addToSystemPackages = true;
    extraPackages = with pkgs; [
      git
      jq
      ripgrep
    ];
  };

  systemd.services.hermes-agent.serviceConfig.EnvironmentFile = [
    "-/var/lib/hermes/env"
  ];

  systemd.services.hermes-dashboard = {
    description = "Hermes Agent Dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "hermes-agent.service"
    ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "/var/lib/hermes/env";

    environment = {
      HERMES_HOME = "/var/lib/hermes/.hermes";
      HOME = "/var/lib/hermes";
    };

    serviceConfig = {
      User = "hermes";
      Group = "hermes";
      WorkingDirectory = "/var/lib/hermes/workspace";
      EnvironmentFile = "-/var/lib/hermes/env";
      ExecStart = "${
        inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default
      }/bin/hermes dashboard --host 0.0.0.0 --port 9119 --no-open";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
  };

  environment.systemPackages = with pkgs; [
    git
    neovim
  ];

  system.stateVersion = "25.05";
}
