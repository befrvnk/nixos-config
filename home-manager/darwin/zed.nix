# Darwin-specific Zed override
#
# On macOS, Zed is installed via Homebrew (nixpkgs build fails - Metal SDK unavailable in sandbox).
# Shared config (extensions, settings) still managed by home-manager via shared/zed.nix.

{ lib, ... }:

{
  # Don't install package - Zed is installed via Homebrew on macOS
  programs.zed-editor.package = lib.mkForce null;
}
