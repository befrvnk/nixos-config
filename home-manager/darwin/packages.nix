# Darwin-compatible packages
#
# Cross-platform CLI tools that work on both NixOS and macOS.
# GUI apps that need native macOS install/update behavior are installed via Homebrew
# (configured in hosts/macbook-darwin/default.nix). GUI apps without a suitable
# Homebrew cask can stay in nixpkgs.

{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # GUI apps
    openchamber

    # CLI tools (cross-platform)
    bat
    bun
    devenv
    eza
    fastfetch
    fd
    fzf

    github-copilot-cli
    helix
    htop
    imagemagick
    lf
    marp-cli
    navi
    nh
    nmap

    rsync
    slidev-cli
    superfile
    tree
    yazi

    # Fonts
    material-symbols
  ];
}
