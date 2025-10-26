{ config, pkgs, ... }:

{
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome = {
    enable = true;
    # This section enables the fractional scaling options (125%, 150%, etc.) 
    # in the GNOME Settings -> Displays menu.
    extraGSettingsOverrides = ''
      [org.gnome.mutter]
      experimental-features=['scale-monitor-framebuffer']
    '';
    # Ensure Mutter is available to provide the GSettings schema
    extraGSettingsOverridePackages = [ pkgs.mutter ];
  };

  services.xserver.xkb.extraLayouts.custom = {
    description = "US with AltGr international";
    languages = [ "eng" ];
    symbolsFile = pkgs.writeText "custom" ''
      xkb_symbols {
        include "us(altgr-intl)"
      };
    '';
  };

  services.printing.enable = true;
  programs.firefox.enable = true;
}
