{
  inputs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules
    inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  networking.hostName = "framework";

  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  services.fwupd = {
    enable = true;
  };

  services.hardware.bolt.enable = false;

  # Disable kmod to avoid infinite recursion with kernel packages
  hardware.framework.enableKmod = false;

  hardware.framework.laptop13.audioEnhancement = {
    enable = true;
    hideRawDevice = true;
    rawDeviceName = "alsa_output.pci-0000_c1_00.6.HiFi__Speaker__sink";
  };

  # 1Password - Use NixOS modules for proper CLI/GUI integration
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "frank" ];
  };

  environment.etc = {
    "1password/custom_allowed_browsers" = {
      text = ''
        .zen-wrapped
      '';
      mode = "0755";
    };
  };
}
