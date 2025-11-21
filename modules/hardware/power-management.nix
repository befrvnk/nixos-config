{ ... }:

{
  # Power management optimizations based on PowerTOP recommendations
  # These settings help extend battery life on Framework laptops

  # Enable basic power management
  powerManagement.enable = true;

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
  ];

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

  # Audio codec power management
  # Enables power saving for Intel HDA audio (also works with AMD)
  # Commented out because of high pipewire and wireplumber CPU usage due to this.
  # There is a communication problem between the audio enhancement and the audio sink.
  # boot.extraModprobeConfig = ''
  #   # Power save timeout in seconds (1 second)
  #   # Audio device will enter power save mode after 1 second of inactivity
  #   options snd_hda_intel power_save=1
  # '';

  # Enable runtime power management for PCI devices
  services.udev.extraRules = ''
    # Enable ASPM (Active State Power Management) for all PCI devices
    # This allows PCIe devices to enter low-power states
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"

    # Enable runtime PM for USB devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="auto"

    # Enable runtime PM for SCSI/SATA devices
    ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="med_power_with_dipm"
  '';

  # TLP - Advanced power management with AC/battery profiles
  # Automatically switches between performance and power-saving modes
  services.tlp = {
    enable = true;
    settings = {
      # CPU frequency scaling governor
      # AC: "performance" for maximum responsiveness
      # Battery: "powersave" for extended battery life
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

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
    };
  };
}
