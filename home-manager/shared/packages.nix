{ pkgs, ... }:

{
  home.packages = with pkgs; [
    acli
    bat
    devenv
    eza
    fastfetch
    fd
    fzf
    helix
    htop
    imagemagick
    lf
    nh
    nmap
    rsync
    superfile
    tree
    yazi
  ];
}
