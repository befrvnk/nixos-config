{ config, pkgs, ... }:

{
  users.users.frank = {
    isNormalUser = true;
    description = "Frank Hermann";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
  };
}
