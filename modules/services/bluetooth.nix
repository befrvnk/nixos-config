{ pkgs, lib, ... }:

let
  bluetoothAutoOnAcScript = pkgs.writeShellScript "bluetooth-auto-on-ac" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.bluez
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.upower
      ]
    }"

    ${builtins.readFile ./bluetooth-auto-on-ac.sh}
  '';
in
{
  # Enable Bluetooth support (but off by default to save power)
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false; # Don't enable on boot - saves ~0.5W
  };

  # Enable bluez service for D-Bus access (needed for ironbar)
  services = {
    blueman.enable = true;

    # Enable UPower for battery information (needed for ironbar)
    upower.enable = true;
  };

  # Turn Bluetooth on automatically when AC power is connected
  # Keeps the default off-on-boot behavior for battery savings
  systemd.services.bluetooth-auto-on-ac = {
    description = "Automatically power on Bluetooth when AC is connected";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "bluetooth.service"
      "upower.service"
    ];
    after = [
      "bluetooth.service"
      "upower.service"
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      ExecStart = "${bluetoothAutoOnAcScript}";
    };
  };
}
