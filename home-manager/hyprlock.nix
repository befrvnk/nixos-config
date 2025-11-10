{
  lib,
  ...
}:
let
  # Custom purple/pink color palette
  palette = {
    base00 = "191033";
    base05 = "f8f8f8";
    base08 = "ff628c";
    base0D = "fad000";
  };
in
{
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
      };

      background = lib.mkForce [
        {
          monitor = "";
          color = "rgba(${palette.base00}ff)";
        }
      ];

      input-field = lib.mkForce [
        {
          monitor = "";
          size = "250, 50";
          outline_thickness = 3;
          outer_color = "rgba(${palette.base0D}ff)";
          inner_color = "rgba(${palette.base00}ff)";
          font_color = "rgba(${palette.base05}ff)";
          fail_color = "rgba(${palette.base08}ff)";
          fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>";
          fail_transition = 0;
          fade_on_empty = false;
          placeholder_text = "Password...";
          dots_size = 0.2;
          dots_spacing = 0.64;
          dots_center = true;
          position = "0, 140";
          halign = "center";
          valign = "bottom";
        }
      ];

      label = lib.mkForce [
        {
          monitor = "";
          text = "$TIME";
          font_size = 66; # 11 * 6
          font_family = "Noto Sans 11";
          color = "rgba(${palette.base05}ff)";
          position = "0, 16";
          valign = "center";
          halign = "center";
        }
        {
          monitor = "";
          text = "$USER";
          color = "rgba(${palette.base05}ff)";
          font_size = 22; # 11 * 2
          font_family = "Noto Sans 11";
          position = "0, 100";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
