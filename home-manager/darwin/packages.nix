# Darwin-compatible packages
#
# Cross-platform CLI tools that work on both NixOS and macOS.
# GUI apps are installed via Homebrew (configured in hosts/macbook-darwin/default.nix).

{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # GUI apps
    notion-app
    slack

    # CLI tools (cross-platform)
    bat
    devenv
    eza
    fd
    fzf
    gh
    helix
    htop
    imagemagick
    lf
    navi
    neofetch
    nh
    nmap
    rsync
    superfile
    tree
    yazi

    # Fonts
    material-symbols
  ];
}
