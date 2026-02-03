{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./hardware-configuration.nix
    ../../modules
  ];

  networking.hostName = "macbook-vm";

  # Simple boot (no secure boot in VM)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # VM integration
  services.spice-vdagentd.enable = true;
  services.qemuGuest.enable = true;

  # Software rendering (UTM doesn't have good GPU passthrough)
  environment.variables.LIBGL_ALWAYS_SOFTWARE = "1";

  # Network (virtio)
  networking.useDHCP = lib.mkDefault true;

  # SSH for easy access from host
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  system.stateVersion = "25.05";
}
