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
    google-antigravity
    supacode

    # CLI tools (cross-platform + Darwin-specific)
    _1password-cli # op CLI; the 1Password app cask does not install it
    bun
    slidev-cli

    # Fonts
    material-symbols
  ];
}
