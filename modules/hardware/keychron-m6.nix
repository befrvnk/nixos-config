{
  config,
  hostConfig,
  lib,
  ...
}:

let
  keychronBattery =
    config.boot.kernelPackages.callPackage ../../pkgs/keychron-battery/package.nix
      { };
in
lib.mkIf (hostConfig.enableKeychronM6 or false) {
  # The Keychron M6 works on Linux via the standard HID stack
  # (hid-generic/usbhid), so there is no special kernel driver to enable.
  # These udev rules expose the device to Keychron Launcher in Chromium-based
  # browsers so button mappings, polling rate, and firmware maintenance work.
  #
  # Known product IDs:
  # - d028: Keychron Ultra-Link 8K receiver
  # - d049: Keychron M6 wired mode (per NixOS Wiki example)
  #
  # Keychron's August 2025 firmware notes also mention fixes for side-scroll
  # rollback issues, so firmware updates are worth checking if the thumb wheel
  # behaves strangely.
  #
  # Battery reporting for the M6's 2.4 GHz receiver is vendor-specific and is
  # not exposed through Linux's standard HID battery paths. Load an extra HID
  # driver so the mouse battery shows up in power_supply/UPower, which in turn
  # feeds desktop widgets such as Ironbar.
  boot.extraModulePackages = [ keychronBattery ];
  boot.kernelModules = [ "keychron_battery" ];

  services.udev.extraRules = ''
    # Keychron M6 via 2.4 GHz receiver
    SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d028", MODE="0660", GROUP="plugdev", TAG+="uaccess"

    # Keychron M6 via USB cable
    SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d049", MODE="0660", GROUP="plugdev", TAG+="uaccess"

    # Keychron Launcher uses hidraw/WebHID access
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", GROUP="plugdev", TAG+="uaccess"
  '';

  users.groups.plugdev = { };
}
