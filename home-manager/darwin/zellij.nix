# Darwin-specific Zellij configuration
#
# Terminal multiplexer with session persistence.
# Includes Catppuccin themes for light/dark mode.
# Switch themes in Zellij: change the `theme` setting below.

_:

{
  xdg.configFile."zellij/config.kdl".force = true;

  programs.zellij = {
    enable = true;

    settings = {
      theme = "catppuccin-latte";
    };

    # Catppuccin themes (latte = light, mocha = dark)
    # Source: https://github.com/catppuccin/zellij
    extraConfig = ''
      themes {
        catppuccin-latte {
          bg "#acb0be"
          fg "#4c4f69"
          red "#d20f39"
          green "#40a02b"
          blue "#1e66f5"
          yellow "#df8e1d"
          magenta "#ea76cb"
          orange "#fe640b"
          cyan "#04a5e5"
          black "#e6e9ef"
          white "#4c4f69"
        }

        catppuccin-mocha {
          bg "#585b70"
          fg "#cdd6f4"
          red "#f38ba8"
          green "#a6e3a1"
          blue "#89b4fa"
          yellow "#f9e2af"
          magenta "#f5c2e7"
          orange "#fab387"
          cyan "#89dceb"
          black "#181825"
          white "#cdd6f4"
        }
      }
    '';
  };
}
