{ pkgs, ... }:

{
  services.udisks2.enable = true;

  # Filesystem utilities for udisks to detect and mount external media
  environment.systemPackages = with pkgs; [
    exfatprogs # exFAT support (SD cards, USB drives)
  ];
}
