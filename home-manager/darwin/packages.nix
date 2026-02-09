# Darwin-compatible packages
#
# Cross-platform CLI tools that work on both NixOS and macOS.
# GUI apps are installed via Homebrew (configured in hosts/macbook-darwin/default.nix).

{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # GUI apps
    notion-app
    raycast
    slack

    # CLI tools (cross-platform)
    bat
    devenv
    eza
    fd
    fzf
    gh
    github-copilot-cli
    goose-cli
    helix
    htop
    imagemagick
    lf
    marp-cli
    navi
    neofetch
    nh
    nmap
    opencode
    rsync
    superfile
    tree
    yazi

    # Fonts
    material-symbols
  ];
}
