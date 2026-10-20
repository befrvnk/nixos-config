{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    acli
    bat
    cloudflared
    devenv
    eza
    fastfetch
    fd
    config.programs.fzf.package
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
