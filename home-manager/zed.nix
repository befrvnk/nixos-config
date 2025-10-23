{ pkgs, pkgs-unstable, ... }:

{
  home.packages = with pkgs; [ nil nixd ];

  programs.zed-editor = {
    enable = true;
    package = pkgs-unstable.zed-editor;
    extensions = [ "nix" ];
  };
}
