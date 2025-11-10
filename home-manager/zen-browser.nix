{ ... }:

{
  programs.zen-browser = {
    enable = true;

    # Configure preferences to use XDG portal for color scheme detection
    policies = {
      Preferences = {
        # Enable XDG Desktop Portal for settings (including color-scheme)
        # 0 = never, 1 = always, 2 = auto (Flatpak only)
        "widget.use-xdg-desktop-portal.settings" = {
          Value = 1;
          Status = "locked";
        };
      };
    };
  };
}
