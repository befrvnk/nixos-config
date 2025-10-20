{ config, pkgs, ... }:

{
  users.users.frank = {
    isNormalUser = true;
    description = "Frank Hermann";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      _1password-gui
      anytype
      bat
      helix
      lf
      neofetch
    ];
  };
}
