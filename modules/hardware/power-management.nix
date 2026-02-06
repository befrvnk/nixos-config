{
  hostConfig,
  pkgs,
  lib,
  ...
}:
let
  isAmd = hostConfig.cpuVendor == "amd";
  abmPath = "/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings";

  # Script for battery profile extras (boost, WiFi power save, ABM, Bluetooth)
  # tuned's [script] plugin runs this when activating the profile
  # Note: tuned's [cpu] boost setting doesn't work, so we set it here
  batteryScript = pkgs.writeShellScript "tuned-battery-extras" ''
    # Disable CPU boost on battery (saves ~2-3W)
    echo 0 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
    # Enable WiFi power save on battery
    ${pkgs.iw}/bin/iw dev wlp192s0 set power_save on 2>/dev/null || true
    # Enable ABM (Adaptive Backlight Management) level 3 for power savings
    echo 3 > ${abmPath} 2>/dev/null || true
    # Turn off Bluetooth on battery (saves ~0.5W, peripherals typically not needed mobile)
    ${pkgs.bluez}/bin/bluetoothctl power off 2>/dev/null || true
  '';

  # Script for AC profile extras (boost, WiFi power save off, ABM off, Bluetooth on)
  acScript = pkgs.writeShellScript "tuned-ac-extras" ''
    # Enable CPU boost on AC for better performance
    echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
    # Disable WiFi power save on AC for better performance
    ${pkgs.iw}/bin/iw dev wlp192s0 set power_save off 2>/dev/null || true
    # Disable ABM on AC for accurate color reproduction
    echo 0 > ${abmPath} 2>/dev/null || true
    # Turn on Bluetooth on AC (for external peripherals at desk)
    ${pkgs.bluez}/bin/bluetoothctl power on 2>/dev/null || true
  '';
in
{
  # Power management using tuned (Red Hat's power management daemon)
  # tuned provides event-based AC/battery switching via upower, eliminating
  # the CPU overhead of udev rules that fire on every battery status update.

  services = {
    # Explicitly disable conflicting power management tools
    tlp.enable = false;
    auto-cpufreq.enable = false;

    tuned = {
      enable = true;

      # Enable power-profiles-daemon API compatibility
      # This allows existing tools (GNOME, KDE, powerprofilesctl) to work
      ppdSupport = true;

      # Configure automatic AC/battery profile switching
      ppdSettings = {
        main = {
          default = "balanced";
          battery_detection = true; # Auto-switch on AC/battery via upower
        };
        profiles = {
          # Use built-in powersave for explicit power-saver requests
          power-saver = "powersave";
          balanced = "framework-ac";
          performance = "throughput-performance";
        };
        battery = {
          # When on battery with "balanced" PPD profile, use our custom battery profile
          # battery_detection auto-switches from balanced to this when unplugging
          balanced = "framework-battery";
        };
      };

      # Custom tuned profiles for Framework laptop
      profiles = {
        # Battery profile: aggressive power savings
        framework-battery = {
          main = {
            summary = "Framework laptop battery profile";
            include = "powersave";
          };
          acpi = {
            platform_profile = "low-power";
          };
          cpu = {
            energy_performance_preference = "power";
          };
          # Disable audio power saving (causes pops on pause/resume)
          # Override powersave profile's timeout=10 setting
          audio = {
            timeout = "0";
          };
          # Script must be in profile dir (tuned security restriction)
          script = {
            script = "script.sh";
          };
        };

        # AC profile: balanced performance
        framework-ac = {
          main = {
            summary = "Framework laptop AC profile";
            include = "balanced";
          };
          acpi = {
            platform_profile = "balanced";
          };
          cpu = {
            energy_performance_preference = "balance_performance";
          };
          # Disable audio power saving (causes pops on pause/resume)
          audio = {
            timeout = "0";
          };
          # Script must be in profile dir (tuned security restriction)
          script = {
            script = "script.sh";
          };
        };
      };
    };

    # Udev rules for device-specific power settings
    # Note: AC/battery switching is handled by tuned via upower events
    udev.extraRules = ''
      # USB autosuspend - enable for all devices except HID (keyboard/mouse)
      # This saves power by putting idle USB devices into suspend mode
      ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
      # Keep HID devices always on to prevent input lag
      # Match when usbhid driver binds (at interface level), then set parent device's power control
      ACTION=="add|bind", SUBSYSTEM=="usb", DRIVERS=="usbhid", ATTR{../power/control}="on"

      # I/O scheduler optimization
      # NVMe: 'none' is optimal (no scheduling overhead, direct submission)
      # SATA SSD: 'mq-deadline' provides fair latency
      # Note: DEVTYPE=="disk" excludes partitions and controllers which don't have schedulers
      ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ENV{DEVTYPE}=="disk", ATTR{queue/scheduler}="none"
      ACTION=="add|change", KERNEL=="sd[a-z]", ENV{DEVTYPE}=="disk", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
    '';
  };

  # Place tuned scripts in profile directories (required by tuned security policy)
  environment.etc = {
    "tuned/profiles/framework-battery/script.sh" = {
      source = batteryScript;
      mode = "0755";
    };
    "tuned/profiles/framework-ac/script.sh" = {
      source = acScript;
      mode = "0755";
    };
  };

  systemd.services = {
    # Reduce tuned stop timeout to avoid long shutdown delays
    tuned.serviceConfig.TimeoutStopSec = 10;

    # Make ABM sysfs writable by users (for toggle-abm and ironbar brightness popup)
    abm-permissions = {
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
    # Allows manual override via ironbar without going through tuned
    platform-profile-permissions = {
      description = "Set platform_profile sysfs permissions for user control";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udev-settle.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/chmod 0666 /sys/firmware/acpi/platform_profile";
        RemainAfterExit = true;
      };
    };

    # Disable audio codec power save controller at runtime
    # Kernel cmdline param doesn't work (module loads too early), so set via sysfs
    # This eliminates pops/clicks when audio streams start/stop
    audio-power-save-controller = {
      description = "Disable snd_hda_intel power save controller";
      wantedBy = [ "multi-user.target" ];
      after = [ "sound.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo N > /sys/module/snd_hda_intel/parameters/power_save_controller'";
        RemainAfterExit = true;
      };
    };
  };

  boot = {
    # Audio power saving DISABLED
    # Enabling power_save causes pipewire/wireplumber to repeatedly handle codec wake/sleep
    # cycles, generating excessive DBUS traffic and CPU overhead. The ~0.1-0.3W savings
    # is offset by the increased CPU usage from constant state transitions.
    # power_save_controller=N disables the controller entirely, preventing pop/click on
    # audio start/stop even when power_save=0 (which only sets the timeout).
    # See: https://www.kernel.org/doc/html/latest/sound/designs/powersave.html
    extraModprobeConfig = ''
      options snd_hda_intel power_save=0 power_save_controller=N
    '';

    # Kernel parameters for power optimization
    kernelParams = [
      # Disable NMI watchdog (saves ~1W)
      # NMI watchdog is used for detecting hard lockups, but not needed for normal use
      "nmi_watchdog=0"
      # PCIe ASPM: Use powersupersave for maximum power savings
      # Previously caused MT7925 WiFi boot failures with TLP, but tuned doesn't have
      # aggressive early udev rules. If WiFi fails, change to "performance".
      # See: docs/mt7925-wifi-boot-failure.md
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
    # Note: tuned also manages some sysctl settings, these are kept as system-wide defaults
    kernel.sysctl = {
      # VM writeback timeout
      # Default: 500 (5 seconds)
      # PowerTOP recommends: 1500 (15 seconds) for better battery life
      # Delays writing dirty pages to disk, reducing disk wakeups
      "vm.dirty_writeback_centisecs" = 1500;

      # Laptop mode - aggressive power saving for disk I/O
      # Batches disk writes to keep disk spun down longer
      "vm.laptop_mode" = 5;
    };
  };

}
