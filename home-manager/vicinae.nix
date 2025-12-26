{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Read the Stylix-generated qtct config and add icon theme
  stylixQt5ctConf = builtins.readFile (
    pkgs.runCommand "stylix-qt5ct" { } ''
          cat > $out << 'EOF'
      [Appearance]
      icon_theme=Papirus
      style=kvantum
      [Fonts]
      fixed="JetBrainsMono Nerd Font,11"
      general="Noto Sans,11"
      EOF
    ''
  );
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
      bluetooth
      nix
      wifi-commander
    ];
  };

  # GTK icon theme (which Qt/vicinae will respect)
  gtk = {
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
