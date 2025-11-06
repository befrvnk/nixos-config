{
  config,
  osConfig,
  pkgs,
  zen-browser,
  android-nixpkgs,
  ...
}:

{
  imports = [
    zen-browser.homeModules.beta
    ./stylix.nix
    ./darkman.nix
    ./git.nix
    ./ssh.nix
    ./zsh.nix
    ./starship.nix
    ./zen-browser.nix
    ./packages.nix
    ./dconf.nix
    (import ./zed.nix { inherit pkgs; })
    (import ./ghostty.nix {
      inherit config pkgs;
      lib = pkgs.lib;
    })
    (import ./android.nix { inherit pkgs android-nixpkgs; })
    (import ./niri/default.nix {
      inherit osConfig pkgs;
      lib = pkgs.lib;
    })
    (import ./dms.nix { inherit pkgs; })
    ./hyprlock.nix
    ./vicinae.nix
  ];

  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";
}
