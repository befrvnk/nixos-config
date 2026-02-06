{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules
    inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # Use CachyOS kernel for best sched_ext/scx_lavd integration
  # 6.17 reached EOL; CachyOS provides optimizations for gaming and power efficiency
  # Available variants: linuxPackages-cachyos-latest, linuxPackages-cachyos-lts
  # Fallback: pkgs.linuxPackages_6_12 if issues arise
  boot = {
    kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
    loader.systemd-boot.enable = lib.mkForce false;
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    # amdgpu.dcdebugmask=0x10: Fix kworker stuck in amdgpu display code causing high I/O
    # pressure. The amdgpu driver has a timeout issue in dmub_srv_wait_for_idle that causes
    # workqueue threads to block, triggering rescue threads and ~80-90% PSI I/O pressure.
    # See: docs/amdgpu-kworker-io-pressure.md
    #
    # Note: PCIe ASPM policy is configured in modules/hardware/power-management.nix
    kernelParams = [
      "amdgpu.dcdebugmask=0x10"
    ];

    # Blacklist UCSI modules to fix high I/O pressure and blocked kworker processes
    # Bug: Linux 6.9+ queries GET_CABLE_PROPERTY which Framework's EC doesn't support
    # Causes: ucsi_acpi USBC000:00: unknown error 0, blocked kworker/u97:*+events_unbound
    # USB-C charging and DisplayPort Alt Mode still work without these modules
    # Tracking: https://github.com/FrameworkComputer/SoftwareFirmwareIssueTracker/issues/3
    # See: docs/ucsi-usbc-io-pressure.md for full details
    blacklistedKernelModules = [
      "ucsi_acpi"
      "typec_ucsi"
    ];
  };

  networking.hostName = "framework";

  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  services.fwupd.enable = true;
  services.hardware.bolt.enable = false;

  # Disable kmod to avoid infinite recursion with kernel packages
  hardware.framework.enableKmod = false;

  hardware.framework.laptop13.audioEnhancement = {
    enable = true;
    hideRawDevice = true;
    # Device name changed from HiFi to analog-stereo after disabling UCM profiles
    # When UCM is re-enabled: "alsa_output.pci-0000_c1_00.6.HiFi__Speaker__sink"
    rawDeviceName = "alsa_output.pci-0000_c1_00.6.analog-stereo";
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
