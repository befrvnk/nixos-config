{ pkgs, ... }:

{
  # Runtime colors come from Noctalia's built-in template, not Stylix.
  stylix.targets.ghostty.enable = false;

  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;
    settings = {
      # The built-in apply hook skips editing the managed config when this
      # literal reference already exists. Only the separate theme is writable.
      theme = "noctalia";

      # Fix Shift+Enter for Claude Code
      # https://github.com/anthropics/claude-code/issues/1282
      keybind = [
        "shift+enter=text:\\x1b\\r"
      ];
    };
  };

  xdg.configFile."ghostty/config".force = true;
}
