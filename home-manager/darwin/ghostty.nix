# Darwin-specific Ghostty configuration
#
# On macOS, Ghostty is installed via Homebrew (not available in nixpkgs for darwin).
# Uses system defaults for theming - macOS handles light/dark mode automatically.

{ ... }:

{
  programs.ghostty = {
    enable = true;
    # Don't install package - Ghostty is installed via Homebrew on macOS
    package = null;

    settings = {
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
