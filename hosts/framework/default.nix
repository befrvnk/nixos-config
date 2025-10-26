{ nixos-hardware, lanzaboote, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules
      nixos-hardware.nixosModules.framework-amd-ai-300-series
      lanzaboote.nixosModules.lanzaboote
    ];

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  networking.hostName = "framework";

  services.fwupd = {
    enable = true;
  };

  hardware.framework.laptop13.audioEnhancement = {
    enable = true;
    hideRawDevice = false;
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
