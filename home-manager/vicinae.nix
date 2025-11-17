{ pkgs, lib, ... }:
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
    # Disable layer shell mode - it causes Wayland protocol errors with niri
    # Layer shell is designed for panels/docks but isn't fully compatible with niri
    # Using regular window mode (useLayerShell = false) works correctly
    useLayerShell = false;

    # Base settings - darkman script will modify the theme at runtime
    settings = {
      theme = {
        name = "catppuccin-mocha"; # Default dark theme
      };
    };
  };

  # Force overwrite vicinae config - needed because darkman modifies this file
  xdg.configFile."vicinae/vicinae.json".force = true;

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
