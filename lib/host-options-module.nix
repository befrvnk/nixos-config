{
  lib,
  config,
  hostDefaults,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.my.host = {
    hostname = mkOption {
      type = types.str;
      default = hostDefaults.hostname;
      readOnly = true;
      description = "Host identifier matching the hosts/ directory name.";
    };

    system = mkOption {
      type = types.str;
      default = hostDefaults.system;
      readOnly = true;
      description = "Target system string for this host.";
    };

    primaryUser = mkOption {
      type = types.str;
      default = hostDefaults.primaryUser;
      readOnly = true;
      description = "Primary user managed by this host configuration.";
    };

    homeDirectory = mkOption {
      type = types.str;
      default = hostDefaults.homeDirectory;
      readOnly = true;
      description = "Absolute home directory for the primary user.";
    };

    cpuVendor = mkOption {
      type = types.enum [
        "amd"
        "intel"
      ];
      default = hostDefaults.cpuVendor or "intel";
      readOnly = true;
      description = "CPU vendor used for hardware-specific configuration.";
    };

    hasFingerprint = mkOption {
      type = types.bool;
      default = hostDefaults.hasFingerprint or false;
      readOnly = true;
      description = "Whether the host has a fingerprint reader.";
    };

    hasTouchscreen = mkOption {
      type = types.bool;
      default = hostDefaults.hasTouchscreen or false;
      readOnly = true;
      description = "Whether the host has a touchscreen.";
    };

    enableAndroid = mkOption {
      type = types.bool;
      default = hostDefaults.enableAndroid or false;
      readOnly = true;
      description = "Enable Android development host extras.";
    };

    enableKeychronM6 = mkOption {
      type = types.bool;
      default = hostDefaults.enableKeychronM6 or false;
      readOnly = true;
      description = "Enable Keychron M6 mouse support.";
    };

    enableNuphy = mkOption {
      type = types.bool;
      default = hostDefaults.enableNuphy or false;
      readOnly = true;
      description = "Enable NuPhy keyboard support.";
    };

    wifiInterface = mkOption {
      type = types.nullOr types.str;
      default = hostDefaults.wifiInterface or null;
      readOnly = true;
      description = "Optional Wi-Fi interface used by power-management helpers.";
    };

    abmPath = mkOption {
      type = types.nullOr types.str;
      default = hostDefaults.abmPath or null;
      readOnly = true;
      description = "Optional AMD ABM sysfs path.";
    };

    platformProfilePath = mkOption {
      type = types.nullOr types.str;
      default = hostDefaults.platformProfilePath or "/sys/firmware/acpi/platform_profile";
      readOnly = true;
      description = "Optional sysfs path for platform profile control.";
    };
  };

  config._module.args.hostConfig = config.my.host;
}
