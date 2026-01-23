{ pkgs, ... }:

{
  users.users.frank = {
    isNormalUser = true;
    description = "Frank Hermann";
    extraGroups = [
      "i2c" # Access to I2C devices for external monitor control (ddcutil)
      "input" # Access to input devices for stasis idle manager (libinput)
      "networkmanager" # Network management permissions
      "plugdev" # Access to USB/HID devices (e.g., NuPhy keyboards via WebHID)
      "wheel" # Sudo access
    ];
    shell = pkgs.nushell;
  };
}
