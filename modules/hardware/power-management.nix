{
  lib,
  hostConfig,
  pkgs,
  ...
}:
let
  isAmd = hostConfig.cpuVendor == "amd";
  abmPath = "/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings";

  # Script for automatic power profile switching based on AC/battery state
  # Uses direct sysfs writes instead of PPD (PPD's boost control broken on kernel 6.17)
  powerProfileAutoScript = pkgs.writeShellScript "power-profile-auto" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.iw}/bin:$PATH"

    set_power_saver() {
      echo "low-power" > /sys/firmware/acpi/platform_profile 2>/dev/null || true
      for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        echo "power" > "$epp" 2>/dev/null || true
      done
      # Disable CPU boost on battery (saves ~2-3W)
      echo 0 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
      # Enable WiFi power save on battery
      iw dev wlp192s0 set power_save on 2>/dev/null || true
      # Enable ABM (Adaptive Backlight Management) for display power savings
      # Level 3 = maximum power savings (reduces backlight, increases contrast)
      echo 3 > /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings 2>/dev/null || true
    }

    set_balanced() {
      echo "balanced" > /sys/firmware/acpi/platform_profile 2>/dev/null || true
      for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        echo "balance_performance" > "$epp" 2>/dev/null || true
      done
      # Enable CPU boost on AC for better performance
      echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
      # Disable WiFi power save on AC for better performance
      iw dev wlp192s0 set power_save off 2>/dev/null || true
      # Disable ABM on AC for accurate color reproduction
      echo 0 > /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings 2>/dev/null || true
    }

    # Set initial state based on current power source
    if [ "$(cat /sys/class/power_supply/AC*/online 2>/dev/null)" = "1" ]; then
      set_balanced
    else
      set_power_saver
    fi

    # Monitor upower for AC/battery changes
    ${pkgs.upower}/bin/upower --monitor-detail | while read -r line; do
      if echo "$line" | grep -q "on-battery"; then
        if echo "$line" | grep -q "yes"; then
          set_power_saver
        else
          set_balanced
        fi
      fi
    done
  '';
in
{
  # Power management optimizations based on PowerTOP recommendations
  # These settings help extend battery life on laptops

  # Enable power-profiles-daemon (Framework/AMD recommended for modern AMD laptops)
  # PPD coordinates platform profile and EPP via the amd-pmf driver
  # Note: PPD may fail on some hardware, power-profile-auto service provides fallback
  services.power-profiles-daemon.enable = true;

  # Automatic power profile switching based on AC/battery state
  # Runs as system service (needs root for sysfs writes)
  systemd.services.power-profile-auto = {
    description = "Automatic power profile switching on AC/battery";
    wantedBy = [ "multi-user.target" ];
    after = [ "power-profiles-daemon.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${powerProfileAutoScript}";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # Make ABM sysfs writable by users (for toggle-abm and ironbar brightness popup)
  systemd.services.abm-permissions = {
    description = "Set ABM sysfs permissions for user control";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/chmod 0666 ${abmPath}";
      RemainAfterExit = true;
    };
  };

  # Make platform_profile writable by users (for ironbar power profile switching)
  # PPD's boost control is broken on kernel 6.17 + amd_pstate EPP mode, so we
  # bypass it and write directly to platform_profile from user scripts
  systemd.services.platform-profile-permissions = {
    description = "Set platform_profile sysfs permissions for user control";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/chmod 0666 /sys/firmware/acpi/platform_profile";
      RemainAfterExit = true;
    };
  };

  # Audio power saving DISABLED
  # Enabling power_save causes pipewire/wireplumber to repeatedly handle codec wake/sleep
  # cycles, generating excessive DBUS traffic and CPU overhead. The ~0.1-0.3W savings
  # is offset by the increased CPU usage from constant state transitions.
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=0
  '';

  # Kernel parameters for power optimization
  boot.kernelParams = [
    # Disable NMI watchdog (saves ~1W)
    # NMI watchdog is used for detecting hard lockups, but not needed for normal use
    "nmi_watchdog=0"
    # PCIe ASPM: Use powersupersave for maximum power savings
    # Previously caused MT7925 WiFi boot failures with TLP, but PPD doesn't have
    # aggressive early udev rules. Testing if this works with PPD.
    # If WiFi fails to boot, change to "performance". See: docs/mt7925-wifi-boot-failure.md
    "pcie_aspm.policy=powersupersave"
    # RCU Lazy: batch RCU callbacks during idle for 5-10% power savings
    # Allows deeper CPU sleep states at idle; no performance downside
    "rcutree.enable_rcu_lazy=1"
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

  # CPU boost is now controlled by power-profile-auto service (more reliable than udev)

  services.udev.extraRules = ''
    # USB autosuspend - enable for all devices except HID (keyboard/mouse)
    # This saves power by putting idle USB devices into suspend mode
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
    # Keep HID devices always on to prevent input lag
    # Match when usbhid driver binds (at interface level), then set parent device's power control
    ACTION=="add|bind", SUBSYSTEM=="usb", DRIVERS=="usbhid", ATTR{../power/control}="on"

    # I/O scheduler optimization
    # NVMe: 'none' is optimal (no scheduling overhead, direct submission)
    # SATA SSD: 'mq-deadline' provides fair latency
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
  '';
}
