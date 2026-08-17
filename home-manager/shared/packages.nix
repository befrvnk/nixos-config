{ pkgs, ... }:

{
  home.packages = with pkgs; [
    acli
    bat
    cloudflared
    devenv
    eza
    fastfetch
    fd
    fzf
    helix
    htop
    imagemagick
    kleinanzeigen
    lf
    nh
    nmap
    rsync
    superfile
    tree
    yazi
  ];
}
