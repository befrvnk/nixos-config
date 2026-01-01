{ ... }:

{
  boot.initrd.systemd.enable = true;
  security.tpm2.enable = true;

  # ZRAM compressed swap for memory pressure situations
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # CachyOS-style performance optimizations
  # Reference: https://github.com/CachyOS/CachyOS-Settings/blob/master/usr/lib/sysctl.d/70-cachyos-settings.conf
  boot.kernel.sysctl = {
    # === Memory Management ===

    # Prefer ZRAM over dropping file cache
    # With ZRAM, higher values (100-200) recommended since swap is fast (RAM speed)
    # 180 is aggressive but safe - compresses inactive pages, preserves file cache
    "vm.swappiness" = 180;

    # Preserve VFS (directory/inode) cache longer
    # Default 100 reclaims aggressively; 50 keeps file metadata in memory
    # Improves performance for IDEs, file managers, build systems
    "vm.vfs_cache_pressure" = 50;

    # Fixed thresholds for dirty page writeback (vs percentage-based defaults)
    # More predictable write behavior, prevents sudden I/O bursts
    "vm.dirty_bytes" = 268435456; # 256MB - process flushes at this threshold
    "vm.dirty_background_bytes" = 67108864; # 64MB - background flush starts here

    # Read single page from swap (2^0 = 1 page)
    # Default 3 (8 pages) assumes sequential access benefits
    # For ZRAM/SSD, reading exactly what's needed is faster
    "vm.page-cluster" = 0;

    # === Network ===

    # Larger network packet queue (default: 1000)
    # Prevents packet drops during traffic bursts (WiFi 6E, high-speed transfers)
    "net.core.netdev_max_backlog" = 4096;

    # === File System ===

    # Maximum file handles system-wide (default: ~100k)
    # Prevents "too many open files" for browsers, dev servers, containers
    "fs.file-max" = 2097152;

    # === Security ===

    # Hide kernel pointers from /proc/kallsyms (security hardening)
    # Makes kernel exploits harder; may affect debugging tools
    "kernel.kptr_restrict" = 2;

    # Suppress kernel console messages (only critical errors)
    # Messages still go to dmesg/journal
    "kernel.printk" = "3 3 3 3";
  };

  # Transparent Hugepages optimization
  # defer+madvise: apps opt-in via madvise(), defrag is background (non-blocking)
  # Reduces latency spikes from memory compaction
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise"
    "w /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 0"
  ];

  # Note: Power profile switching is now handled by power-profiles-daemon
  # which uses D-Bus and polkit for authorization, no sudo config needed

  # Let the Framework hardware module handle kernel selection
  # boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";

  i18n = {
    defaultLocale = "en_US.UTF-8";
  };

  programs.zsh.enable = true;

  # Enable nix-ld for running dynamically linked executables
  programs.nix-ld = {
    enable = true;
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Allow the user to configure binary caches (needed for devenv)
    trusted-users = [
      "root"
      "frank"
    ];
  };

  # Configure systemd-logind for proper lid handling
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "suspend";
    IdleAction = "ignore";
  };

  # Enable USB wake only for keyboards
  services.udev.extraRules = ''
    # First, disable wake for all USB devices by default
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"

    # Then enable wake only for external keyboard
    # NuPhy Air75 V3
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="19f5", ATTRS{idProduct}=="1028", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"
  '';

  system.stateVersion = "25.05";
}
