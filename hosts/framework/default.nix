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

  # Downgrade kernel to 6.17 to avoid VPE queue reset crash during suspend/resume
  # Bug: commit 31ab31433c9b in 6.18 causes amdgpu VPE failures
  # Remove when 6.19+ or patched 6.18.x is available in nixpkgs
  boot.kernelPackages = pkgs.linuxPackages_6_17;

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

  # MediaTek MT7925 WiFi: Set conservative ASPM policy to prevent "driver own failed"
  # errors during boot. The WiFi card fails to initialize if aggressive ASPM puts it
  # in a low-power state before driver probe. Module-level disable_aspm=1 was too late.
  # "performance" keeps ASPM enabled but avoids aggressive power states.
  # If this still fails, fall back to "pcie_aspm=off".
  #
  # amdgpu.dcdebugmask=0x10: Fix kworker stuck in amdgpu display code causing high I/O
  # pressure. The amdgpu driver has a timeout issue in dmub_srv_wait_for_idle that causes
  # workqueue threads to block, triggering rescue threads and ~80-90% PSI I/O pressure.
  # See: docs/amdgpu-kworker-io-pressure.md
  boot.kernelParams = [
    "pcie_aspm.policy=performance"
    "amdgpu.dcdebugmask=0x10"
  ];

  # Blacklist UCSI modules to fix high I/O pressure and blocked kworker processes
  # Bug: Linux 6.9+ queries GET_CABLE_PROPERTY which Framework's EC doesn't support
  # Causes: ucsi_acpi USBC000:00: unknown error 0, blocked kworker/u97:*+events_unbound
  # USB-C charging and DisplayPort Alt Mode still work without these modules
  # Tracking: https://github.com/FrameworkComputer/SoftwareFirmwareIssueTracker/issues/3
  # See: docs/ucsi-usbc-io-pressure.md for full details
  boot.blacklistedKernelModules = [
    "ucsi_acpi"
    "typec_ucsi"
  ];

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
