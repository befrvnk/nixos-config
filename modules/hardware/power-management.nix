{
  lib,
  hostConfig,
  ...
}:
let
  isAmd = hostConfig.cpuVendor == "amd";
in
{
  # Power management optimizations based on PowerTOP recommendations
  # These settings help extend battery life on laptops

  # Disable power-profiles-daemon (conflicts with TLP)
  # power-profiles-daemon is often enabled by default in desktop environments
  # We use TLP instead for more comprehensive power management
  services.power-profiles-daemon.enable = false;

  # NOTE: cpuFreqGovernor is managed by TLP (see below)
  # TLP sets different governors based on AC/battery state

  # Kernel parameters for power optimization
  boot.kernelParams = [
    # Disable NMI watchdog (saves ~1W)
    # NMI watchdog is used for detecting hard lockups, but not needed for normal use
    "nmi_watchdog=0"
  ]
  # AMD-specific: Use P-State active (EPP) mode for hardware-controlled frequency scaling
  # Active mode: hardware autonomously controls frequency based on Energy Performance Preference (EPP)
  # Required for scx_lavd --autopower to read EPP and adjust scheduling behavior
  # Better idle efficiency and works well with sched_ext schedulers
  ++ lib.optionals isAmd [ "amd_pstate=active" ];

  # Runtime kernel settings
  boot.kernel.sysctl = {
    # VM writeback timeout
    # Default: 500 (5 seconds)
    # PowerTOP recommends: 1500 (15 seconds) for better battery life
    # Delays writing dirty pages to disk, reducing disk wakeups
    "vm.dirty_writeback_centisecs" = 1500;

    # Laptop mode - aggressive power saving for disk I/O
    # Batches disk writes to keep disk spun down longer
    "vm.laptop_mode" = 5;
  };

  # Runtime power management is handled by TLP (see below)
  # Previously, we had aggressive udev rules here that enabled power management
  # for all PCI/USB devices immediately on boot. This caused race conditions where
  # devices (especially the mt7925e WiFi card) would be put into low-power states
  # before their drivers fully initialized, leading to "driver own failed" errors.
  # TLP's RUNTIME_PM_ON_AC/BAT settings handle this more safely by applying power
  # management after the system has fully booted.

  # TLP - Advanced power management with AC/battery profiles
  # Automatically switches between performance and power-saving modes
  services.tlp = {
    enable = true;
    settings = {
      # CPU frequency scaling governor
      # schedutil: Scheduler-driven frequency scaling for optimal responsiveness and efficiency
      # Works well with both AMD P-State and Intel P-State drivers
      # Used on both AC and battery since powersave is too sluggish for typical tasks
      # (video playback, code compilation) while schedutil is still power-efficient
      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "schedutil";

      # CPU boost (turbo)
      # AC: Enable turbo for better performance
      # Battery: Disable turbo to save power (~2-3W savings)
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;

      # AMD Platform Profile
      # Controls power/performance balance at the platform level
      # Options: "low-power", "balanced", "performance"
      PLATFORM_PROFILE_ON_AC = "balanced";
      PLATFORM_PROFILE_ON_BAT = "low-power";

      # Runtime Power Management
      # Enables automatic power management for PCIe/USB devices
      RUNTIME_PM_ON_AC = "auto";
      RUNTIME_PM_ON_BAT = "auto";

      # PCIe Active State Power Management (ASPM)
      # Allows PCIe devices to enter low-power states
      # "default" uses system defaults, which are usually conservative
      PCIE_ASPM_ON_AC = "default";
      PCIE_ASPM_ON_BAT = "powersupersave";

      # Wi-Fi power saving
      # Battery: Enable power management
      # AC: Disable for better performance/latency
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";

      # USB autosuspend
      # Automatically suspend USB devices when idle
      USB_AUTOSUSPEND = 1;

      # Exclude input devices from USB autosuspend
      # This ensures keyboards and mice stay responsive and can wake the system
      # Device classes: usbhid = USB HID devices (keyboards, mice)
      USB_EXCLUDE_BTUSB = 1; # Keep bluetooth adapters active
      USB_EXCLUDE_PHONE = 1; # Keep phones/tablets active
      USB_EXCLUDE_WWAN = 1; # Keep WWAN modems active

      # Exclude USB HID devices (mice, keyboards) from autosuspend
      # This is critical to prevent input lag and recognition delays
      USB_DENYLIST = "usbhid";

      # NVMe power management
      # ALPM: Aggressive Link Power Management
      # Helps NVMe SSDs enter deeper power states
      AHCI_RUNTIME_PM_ON_AC = "auto";
      AHCI_RUNTIME_PM_ON_BAT = "auto";

      # Audio power management
      # Disable audio power saving to prevent:
      # 1. High pipewire/wireplumber CPU usage (communication issues with audio processing)
      # 2. Incorrect volume reporting (wpctl returns 1.0 when suspended instead of actual volume)
      # 3. Volume changes not being visible in UI until audio is played
      # Setting to 0 keeps audio codec always active, preventing these issues
      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 0;
    };
  };
}
