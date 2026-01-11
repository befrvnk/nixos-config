# Overlay to use Zed from a pinned nixpkgs revision with cached binary
# This avoids compiling Zed from source when nixpkgs-unstable has a newer
# version that hasn't been built by Hydra yet.
#
# To update: find a cached revision at https://hydra.nixos.org/job/nixpkgs/trunk/zed-editor.x86_64-linux
# Then update nixpkgs-zed.url in flake.nix
{ inputs }:
final: prev: {
  zed-editor = (import inputs.nixpkgs-zed { system = final.system; }).zed-editor;
}
