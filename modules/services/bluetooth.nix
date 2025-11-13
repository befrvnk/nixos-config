{ ... }:

{
  # Enable Bluetooth support
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Enable bluez service for D-Bus access (needed for ironbar)
  services.blueman.enable = true;

  # Enable UPower for battery information (needed for ironbar)
  services.upower.enable = true;
}
