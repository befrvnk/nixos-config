{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  stylixQt5ctConf = ''
    [Appearance]
    icon_theme=Papirus
    style=kvantum
    [Fonts]
    fixed="JetBrainsMono Nerd Font,11"
    general="Noto Sans,11"
  '';

  localGeminiTextTools =
    inputs.vicinae.packages.${pkgs.stdenv.hostPlatform.system}.mkVicinaeExtension
      {
        pname = "vicinae-extension-gemini-text-tools";
        version = "0";
        src = ./vicinae/extensions/gemini-text-tools;
      };
in
{
  services.vicinae = {
    enable = true;

    # Use the module's systemd integration
    systemd.enable = true;

    settings = {
      launcher_window = {
        opacity = 1.0;
        client_side_decorations = {
          enabled = true;
        };
        layer_shell = {
          enabled = false; # Disabled for niri compatibility
        };
      };
      theme = {
        light = {
          name = "stylix";
          icon_theme = "Papirus";
        };
        dark = {
          name = "stylix";
          icon_theme = "Papirus";
        };
      };
    };

    extensions = with inputs.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system}; [
      # bluetooth # TODO: re-enable once usocket builds with Node.js 24
      localGeminiTextTools
      nix
      wifi-commander
    ];
  };

  # GTK icon theme (which Qt/vicinae will respect)
  gtk = {
    gtk4.theme = null;
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus";
    };
  };

  # Override Stylix's Qt config to add icon theme
  stylix.targets.qt.enable = lib.mkForce false;

  home.file.".config/qt5ct/qt5ct.conf".text = stylixQt5ctConf;
  home.file.".config/qt6ct/qt6ct.conf".text = stylixQt5ctConf;
}
