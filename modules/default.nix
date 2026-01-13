{
  imports = [
    # Core configuration
    ./users.nix
    ./system/core.nix

    # System packages and configuration
    ./system/packages.nix
    ./system/security.nix
    ./system/xkb-custom.nix

    # Hardware
    ./hardware/android.nix
    ./hardware/logitech.nix
    ./hardware/nuphy.nix
    ./hardware/fprintd
    ./hardware/fprintd/lid-management.nix
    ./hardware/power-management.nix

    # Desktop environment
    ./desktop/greetd.nix
    ./desktop/niri.nix

    # Services
    ./services/darkman.nix
    ./services/keyd.nix
    ./services/oomd.nix
    ./services/pipewire.nix
    ./services/bluetooth.nix
    ./services/udisks.nix
    ./services/scx.nix

    # Theming
    ./theming/stylix.nix
  ];
}
