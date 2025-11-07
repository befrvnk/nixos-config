{ pkgs, ... }:

{
  # udev rules for NuPhy keyboards to work with NuphyIO web configurator
  # This allows Chromium and other browsers to access the keyboard via WebHID
  services.udev.extraRules = ''
    # NuPhy keyboards (vendor ID: 19f5)
    SUBSYSTEM=="usb", ATTR{idVendor}=="19f5", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="19f5", MODE="0666", GROUP="plugdev"
  '';

  # Ensure the plugdev group exists
  users.groups.plugdev = {};
}
