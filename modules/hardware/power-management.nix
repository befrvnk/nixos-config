{
  lib,
  hostConfig,
  pkgs,
  ...
}:
let
  isAmd = hostConfig.cpuVendor == "amd";
  abmPath = "/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings";

  stateFile = "/run/power-profile-state";

  # Script for power-saver mode (on battery)
  setPowerSaver = pkgs.writeShellScript "set-power-saver" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.iw}/bin:${pkgs.systemd}/bin:$PATH"
    # Only apply if state changed (udev fires constantly)
    [ -f ${stateFile} ] && [ "$(cat ${stateFile})" = "battery" ] && exit 0
    echo "battery" > ${stateFile}
    logger -t power-profile "Switching to power-saver (on battery)"
    echo "low-power" > /sys/firmware/acpi/platform_profile 2>/dev/null || true
    for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      echo "power" > "$epp" 2>/dev/null || true
    done
    # Disable CPU boost on battery (saves ~2-3W)
    echo 0 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
    # Enable WiFi power save on battery
    iw dev wlp192s0 set power_save on 2>/dev/null || true
    # Enable ABM (Adaptive Backlight Management) for display power savings
    echo 3 > /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings 2>/dev/null || true
  '';

  # Script for balanced mode (on AC)
  setBalanced = pkgs.writeShellScript "set-balanced" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.iw}/bin:${pkgs.systemd}/bin:$PATH"
    # Only apply if state changed (udev fires constantly)
    [ -f ${stateFile} ] && [ "$(cat ${stateFile})" = "ac" ] && exit 0
    echo "ac" > ${stateFile}
    logger -t power-profile "Switching to balanced (AC connected)"
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
  '';

  # Script to apply correct profile based on current AC state (for boot)
  # Removes state file first to force applying the profile
  applyPowerProfile = pkgs.writeShellScript "apply-power-profile" ''
    rm -f ${stateFile}
    if [ "$(cat /sys/class/power_supply/ACAD/online 2>/dev/null)" = "1" ]; then
      ${setBalanced}
    else
      ${setPowerSaver}
    fi
  '';
in
{
  # Power management optimizations based on PowerTOP recommendations
  # These settings help extend battery life on laptops

  # Enable power-profiles-daemon (Framework/AMD recommended for modern AMD laptops)
  # PPD coordinates platform profile and EPP via the amd-pmf driver
  # Note: PPD may fail on some hardware, power-profile-auto service provides fallback
  services.power-profiles-daemon.enable = true;

  # Apply correct power profile at boot based on current AC state
  systemd.services.power-profile-init = {
    description = "Set initial power profile based on AC state";
    wantedBy = [ "multi-user.target" ];
    after = [ "power-profiles-daemon.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${applyPowerProfile}";
      RemainAfterExit = true;
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

  services.udev.extraRules = ''
    # Power profile switching based on battery status (ACAD doesn't generate events)
    # Use ENV instead of ATTR - ENV is set in the uevent, ATTR requires sysfs read
    SUBSYSTEM=="power_supply", KERNEL=="BAT1", ENV{POWER_SUPPLY_STATUS}=="Charging", RUN+="${setBalanced}"
    SUBSYSTEM=="power_supply", KERNEL=="BAT1", ENV{POWER_SUPPLY_STATUS}=="Discharging", RUN+="${setPowerSaver}"

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
