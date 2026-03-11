_:

{
  # Enable Bluetooth support (but off by default to save power)
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false; # Don't enable on boot - saves ~0.5W
  };

  # Enable bluez service for D-Bus access (needed for ironbar)
  services.blueman.enable = true;

  # Enable UPower for battery information (needed for ironbar)
  services.upower.enable = true;
}
