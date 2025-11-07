{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nil
    nixd
  ];

  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor;
    extensions = [ "nix" ];
  };
}
