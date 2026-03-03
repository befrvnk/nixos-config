# Darwin-compatible packages
#
# Cross-platform CLI tools that work on both NixOS and macOS.
# GUI apps are installed via Homebrew (configured in hosts/macbook-darwin/default.nix).

{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # GUI apps
    ghostree # sidequery/ghostree - Ghostty terminal with native git worktrees
    notion-app
    raycast
    slack
    spotify
    # CLI tools (cross-platform)
    bat
    bun
    devenv
    eza
    fd
    fzf
    gh
    github-copilot-cli
    helix
    htop
    imagemagick
    lf
    marp-cli
    navi
    neofetch
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
