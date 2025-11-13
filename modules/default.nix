{
  imports = [
    # Core configuration
    ./users.nix
    ./system/core.nix

    # System packages and configuration
    ./system/packages.nix
    ./system/xkb-custom.nix

    # Hardware
    ./hardware/nuphy.nix

    # Desktop environment
    ./desktop/display.nix
    ./desktop/greetd.nix
    ./desktop/niri.nix

    # Services
    ./services/darkman.nix
    ./services/keyd.nix
    ./services/pipewire.nix
    ./services/bluetooth.nix

    # Theming
    ./theming/stylix.nix
  ];
}
