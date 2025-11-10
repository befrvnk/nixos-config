{ pkgs, ... }:

{
  # NuPhy Keyboard Support
  # =====================
  # This module enables NuPhy keyboards to work with the NuphyIO web configurator
  # in Chromium and other browsers via the WebHID API.
  #
  # Fix source: https://www.reddit.com/r/NuPhy/comments/1l4n3is/
  #
  # The plugdev group:
  # - plugdev is a standard Linux group for users who can access removable devices
  # - Members of this group can access USB and HID devices without root privileges
  # - Required for WebHID API in browsers to communicate with keyboards
  # - Users must be added to this group (see modules/users.nix)
  #
  # After rebuilding, users in plugdev can:
  # - Configure NuPhy keyboards via nuphy.io in Chromium
  # - Update keyboard firmware through the web interface
  # - Modify keyboard settings without sudo

  # udev rules for NuPhy keyboards (vendor ID: 19f5)
  # These rules grant the plugdev group access to NuPhy USB and HID devices
  services.udev.extraRules = ''
    # NuPhy keyboards - USB subsystem
    SUBSYSTEM=="usb", ATTR{idVendor}=="19f5", MODE="0666", GROUP="plugdev"
    # NuPhy keyboards - HID raw interface (used by WebHID)
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="19f5", MODE="0666", GROUP="plugdev"
  '';

  # Create the plugdev group
  # Note: Users must be explicitly added to this group to gain access
  users.groups.plugdev = { };
}
