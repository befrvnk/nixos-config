{
  lib,
  hostConfig,
  pkgs,
  ...
}:
let
  isAmd = hostConfig.cpuVendor == "amd";

  # Script for automatic power profile switching based on AC/battery state
  powerProfileAutoScript = pkgs.writeShellScript "power-profile-auto" ''
    export PATH="${pkgs.power-profiles-daemon}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.iw}/bin:$PATH"

    set_power_saver() {
      powerprofilesctl set power-saver
      # PPD may fail to apply settings on some hardware, set directly as fallback
      echo "low-power" > /sys/firmware/acpi/platform_profile 2>/dev/null || true
      for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        echo "power" > "$epp" 2>/dev/null || true
      done
      # Enable WiFi power save on battery
      iw dev wlp192s0 set power_save on 2>/dev/null || true
      # Enable ABM (Adaptive Backlight Management) for display power savings
      # Level 3 = maximum power savings (reduces backlight, increases contrast)
      echo 3 > /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings 2>/dev/null || true
    }

    set_balanced() {
      powerprofilesctl set balanced
      # PPD may fail to apply settings on some hardware, set directly as fallback
      echo "balanced" > /sys/firmware/acpi/platform_profile 2>/dev/null || true
      for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        echo "balance_performance" > "$epp" 2>/dev/null || true
      done
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

  # CPU boost control based on power source
  # PPD doesn't control CPU boost, so we use udev rules
  # Disabling boost on battery saves ~2-3W
  services.udev.extraRules = ''
    # Disable CPU boost when on battery
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="${pkgs.bash}/bin/bash -c 'echo 0 > /sys/devices/system/cpu/cpufreq/boost'"
    # Enable CPU boost when on AC
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="${pkgs.bash}/bin/bash -c 'echo 1 > /sys/devices/system/cpu/cpufreq/boost'"

    # USB autosuspend - enable for all devices except HID (keyboard/mouse)
    # This saves power by putting idle USB devices into suspend mode
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
    # Keep HID devices (class 03) always on to prevent input lag
    ACTION=="add", SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="03", TEST=="power/control", ATTR{power/control}="on"
  '';
}
