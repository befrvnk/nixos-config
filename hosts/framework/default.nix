{
  inputs,
  lib,
  pkgs,
  hostConfig,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules
    ../../modules/profiles/framework.nix
    inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # Use CachyOS LTS kernel: the 7.1.x (cachyos-latest) series has an unfixed
  # mt76/MT7925 regression where WiFi stays "connected" but traffic dies
  # (no ARP/ICMP, throughput ~0), only recoverable by reloading mt7925e.
  # Confirmed by CachyOS forum + upstream commit 37d6538; the 6.18.x LTS
  # works perfectly. Revisit once the 7.1.x regression is fixed upstream.
  # See: docs/mt7925-wifi-boot-failure.md
  boot = {
    binfmt.emulatedSystems = [ "aarch64-linux" ];
    kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-lts;
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

  # hermi (Raspberry Pi, Nanobot) is pinned to 192.168.178.71 via FRITZ!Box
  # fixed lease. DNS (hermi.fritz.box) is NOT used from this machine because
  # the resolver is pinned to NextDNS, so resolve it via /etc/hosts.
  networking.hosts."192.168.178.71" = [
    "hermi"
    "hermi.fritz.box"
  ];

  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  services.fwupd.enable = true;
  services.hardware.bolt.enable = false;

  # CachyOS' kernel derivation does not expose NixOS' kernel.target/buildDTBs attrs yet.
  # The Framework is x86_64, so use the standard bzImage target and disable DTBs.
  system.boot.loader.kernelFile = "bzImage";

  hardware = {
    deviceTree.enable = false;

    framework = {
      # Disable kmod to avoid infinite recursion with kernel packages
      enableKmod = false;

      laptop13.audioEnhancement = {
        enable = true;
        hideRawDevice = true;
        # Device name changed from HiFi to analog-stereo after disabling UCM profiles
        # When UCM is re-enabled: "alsa_output.pci-0000_c1_00.6.HiFi__Speaker__sink"
        rawDeviceName = "alsa_output.pci-0000_c1_00.6.analog-stereo";
      };
    };
  };

  # 1Password - Use NixOS modules for proper CLI/GUI integration
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ hostConfig.primaryUser ];
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
