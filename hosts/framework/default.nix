{
  config,
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
    ../../modules/desktop/umbriel.nix
    ../../modules/profiles/framework.nix
    inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # Keep module aggregation coherent with the kernel provider: the CachyOS kernel is
  # built by Chaotic-Nyx's pinned nixpkgs, whose module trees do not emit the
  # kmodigest certificates main nixpkgs now expects. Revisit this override when
  # changing the kernel provider or its pinned nixpkgs.
  nixpkgs.overlays = [
    (
      final: prev:
      let
        provider = inputs.chaotic.inputs.nixpkgs.legacyPackages.${final.stdenv.hostPlatform.system};
      in
      {
        aggregateModules =
          modules:
          let
            kernel = config.boot.kernelPackages.kernel;
          in
          if (kernel.stdenv or prev.stdenv).outPath == provider.stdenv.outPath then
            provider.aggregateModules modules
          else
            prev.aggregateModules modules;
      }
    )
  ];

  # Keep LTS for the MT7925 MLO traffic-stall regression (Bugzilla 221884).
  # As of 2026-10-22, Linux 7.3/7.2.12 and CachyOS 7.3.0-2 lack the candidate
  # fix. The October 4 v2 was tested on a manually patched 7.3-rc5, not shipped
  # in the official RC. Promote a newer series only after source verification
  # and user-operated MLO testing, not a release-number threshold.
  # See: docs/mt7925-wifi-boot-failure.md
  boot = {
    binfmt.emulatedSystems = [ "aarch64-linux" ];
    # Instantiated from Chaotic-Nyx's own nixpkgs pin, so the kernel resolves to the
    # paths their binary cache actually holds (the `pinned`-overlay rule from the old
    # provider, kept here by referencing legacyPackages instead of our overlay pkgs).
    kernelPackages =
      inputs.chaotic.legacyPackages.${pkgs.stdenv.hostPlatform.system}."linuxPackages_cachyos-lts";
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
    # nixpkgs bug: 8.12.42 (newer Electron) aborts at startup with SIGTRAP because
    # the bundled chrome_crashpad_handler has no RPATH and cannot dlopen libglib-2.0.
    # The package only patches RPATHs for the main binary and a few helpers; the
    # crash handler is spawned with a filtered environment, so LD_LIBRARY_PATH
    # wrappers do not reach it. Patch the crash handlers' RPATH directly.
    # Drop once upstream nixpkgs fixes this: https://github.com/NixOS/nixpkgs/issues/576668
    package = pkgs._1password-gui.overrideAttrs (old: {
      postFixup = (old.postFixup or "") + ''
        for f in chrome_crashpad_handler 1Password-Crash-Handler; do
          patchelf --set-rpath $out/share/1password:${pkgs.glib.out}/lib $out/share/1password/$f
        done
      '';
    });
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
