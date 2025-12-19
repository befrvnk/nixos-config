{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.xdg-utils
  ];
  xdg = {
    autostart.enable = true;
    menus.enable = true;
    mime.enable = true;
    icons.enable = true;
  };

  hardware.graphics.enable = true;

  services.displayManager.sessionPackages = [ pkgs.niri ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    configPackages = [ pkgs.niri ];
  };

  security.polkit.enable = true;

  # Enable gnome-keyring at system level for proper dbus integration
  # PAM configuration in greetd.nix ensures it's unlocked on login
  services.gnome.gnome-keyring.enable = true;

  security.pam.services.swaylock = { };
  programs.dconf.enable = true;
  fonts.enableDefaultPackages = true;
}
