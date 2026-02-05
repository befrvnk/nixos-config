{ pkgs, ... }:

let
  themes = import ../../shared/themes.nix { inherit pkgs; };
in
{
  # Minimal system-level stylix configuration
  # The actual theming is handled by home-manager specialisations
  stylix = {
    enable = true;
    autoEnable = true;
    inherit (themes.dark) base16Scheme;
    image = ../../home-manager/wallpapers/mountain.jpg;

    # Disable version check warnings (we use nixpkgs-unstable for everything)
    enableReleaseChecks = false;

    # Disable automatic home-manager integration since we're manually importing it
    homeManagerIntegration = {
      autoImport = false;
      followSystem = false;
    };
  };
}
