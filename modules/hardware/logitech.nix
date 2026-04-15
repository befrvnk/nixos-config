{ hostConfig, lib, ... }:

lib.mkIf (hostConfig.enableLogitech or false) {
  hardware.logitech.wireless = {
    enable = true;
    enableGraphical = true; # Enables Solaar GUI support
  };
}
