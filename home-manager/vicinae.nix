{...}: {
  services.vicinae = {
    enable = true;
    # Disable layer shell mode - it causes Wayland protocol errors with niri
    # Layer shell is designed for panels/docks but isn't fully compatible with niri
    # Using regular window mode (useLayerShell = false) works correctly
    useLayerShell = false;
  };
}