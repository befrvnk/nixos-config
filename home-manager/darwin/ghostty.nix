# Darwin-specific Ghostty configuration
#
# On macOS, Ghostty is installed via Homebrew (not available in nixpkgs for darwin).
# Uses system defaults for theming - macOS handles light/dark mode automatically.

_:

{
  programs.ghostty = {
    enable = true;
    # Don't install package - Ghostty is installed via Homebrew on macOS
    package = null;

    settings = {
      # Launch nushell via bash login shell to inherit Nix environment
      command = "bash -l -c nu";

      # Follow macOS system appearance (light/dark mode)
      window-theme = "auto";

      # Allow sidebar to extend to the top of the window (used by Ghostree)
      macos-titlebar-style = "transparent";

      # macOS-like minimal theme, follows system light/dark mode
      theme = "light:Apple System Colors Light,dark:Apple System Colors";

      # Fix Shift+Enter for Claude Code
      # https://github.com/anthropics/claude-code/issues/1282
      keybind = [
        "shift+enter=text:\\x1b\\r"
      ];
    };
  };

  # Force overwrite the config file to prevent conflicts
  xdg.configFile."ghostty/config".force = true;
}
