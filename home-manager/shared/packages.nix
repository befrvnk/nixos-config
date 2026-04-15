{ lib, pkgs, ... }:

{
  home.packages =
    (with pkgs; [
      bat
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
    ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.devenv ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.devenvLatest ];
}
