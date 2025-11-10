{ pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    # Essential CLI tools
    git
    vim
    wget
    zsh

    # System security & boot
    tpm2-tss
    sbctl

    # Desktop environment packages
    networkmanager
  ];
}
