{
  programs.btop = {
    enable = true;
    settings = {
      # Theme selection is platform-specific: Noctalia on NixOS, Stylix on Darwin.
      vim_keys = false; # Use default keybindings (arrow keys)
      update_ms = 1000; # Normal update rate (1 second)
    };
  };
}
