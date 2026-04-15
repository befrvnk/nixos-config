{ pkgs, ... }:

{
  home.packages = with pkgs; [
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
