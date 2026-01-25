{
  programs.btop = {
    enable = true;
    settings = {
      # color_theme is managed by Stylix (generates theme from base16 colors)
      vim_keys = false; # Use default keybindings (arrow keys)
      update_ms = 1000; # Normal update rate (1 second)
    };
  };
}
