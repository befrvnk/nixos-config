{ pkgs, ... }:

{
  programs.btop = {
    enable = true;
    settings = {
      # color_theme will be set via specialization in stylix.nix
      vim_keys = false; # Use default keybindings (arrow keys)
      update_ms = 1000; # Normal update rate (1 second)
    };
  };

  # Deploy Catppuccin theme files
  home.file.".config/btop/themes/catppuccin_mocha.theme".source = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme";
    sha256 = "0i263xwkkv8zgr71w13dnq6cv10bkiya7b06yqgjqa6skfmnjx2c";
  };

  home.file.".config/btop/themes/catppuccin_latte.theme".source = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_latte.theme";
    sha256 = "0fqpp6yxkw047dnlh39fxi0zw6scg3cr9dnwb49kl27fspm67sch";
  };
}
