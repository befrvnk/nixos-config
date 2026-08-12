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
    kleinanzeigen
    kleinanzeigen-api
    lf
    nh
    nmap
    rsync
    superfile
    tree
    yazi
  ];
}
