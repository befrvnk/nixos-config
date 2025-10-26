{ lib, pkgs, ... }:

let
  layoutName = "us-umlauts";
in
{
  # Changes to this seem to only apply after a gnome reboot
  services.xserver.xkb.extraLayouts.${layoutName} =
  {
    description = "US layout with German Umlauts on left and right Alt";
    languages = [ "eng" ];
    symbolsFile = pkgs.writeText "us-umlauts"
    ''
      default partial alphanumeric_keys
      xkb_symbols "basic" {
        include "us(basic)"

        name[Group1]="English (US, with German umlauts)";

        key <AC01> { [               a,          A,      adiaeresis,      Adiaeresis ] }; // a A ä Ä
        key <AC02> { [               s,          S,          ssharp,      U1E9E ] }; // s S ß ẞ
        key <AD03> { [               e,          E,      EuroSign,      cent ] };
        key <AD07> { [               u,          U,      udiaeresis,      Udiaeresis ] }; // u U ü Ü
        key <AD09> { [               o,          O,      odiaeresis,      Odiaeresis ] }; // o O ö Ö
      };
    '';
  };

  # Set the keyboard layout and options
  services.xserver.layout = layoutName;
  services.xserver.xkbOptions = "lv3:alt_switch"; # Use left and right alt for special characters

  # The following is for GNOME/GDM. It will override the layout set by services.xserver.layout.
  # It is not strictly necessary if you don't use GNOME, but it's good to have for consistency.
  environment.etc."gdm/greeter.dconf-defaults".text = ''
    [org/gnome/desktop/input-sources]
    sources=[('xkb', '${layoutName}')]
  '';


}
