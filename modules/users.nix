{ pkgs, ... }:

{
  users.users.frank = {
    isNormalUser = true;
    description = "Frank Hermann";
    extraGroups = [
      "networkmanager" # Network management permissions
      "wheel" # Sudo access
      "plugdev" # Access to USB/HID devices (e.g., NuPhy keyboards via WebHID)
      "i2c" # Access to I2C devices for external monitor control (ddcutil)
    ];
    shell = pkgs.zsh;
  };
}
