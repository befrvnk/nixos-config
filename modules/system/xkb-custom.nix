{ pkgs, ... }:

let
  layoutName = "us-umlauts";
in
{
  # Enable X server module just for XKB layout generation
  # We're not actually running X server, but this is needed to generate custom layouts
  services.xserver.enable = true;

  services.xserver.xkb.extraLayouts.${layoutName} = {
    description = "US layout with German Umlauts on left and right Alt";
    languages = [ "eng" ];
    symbolsFile = pkgs.writeText "us-umlauts" ''
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
  services.xserver.xkb.layout = layoutName;
  services.xserver.xkb.options = "lv3:any_alt"; # Use left and right alt for special characters
}
