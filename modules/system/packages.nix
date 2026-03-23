{ pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "electron-38.8.4"
  ];

  environment.systemPackages = with pkgs; [
    # Android development
    android-tools # ADB for device communication

    # Essential CLI tools
    git
    vim
    wget
    zsh

    # System security & boot
    sbctl
    tpm2-tss

    # Desktop environment packages
    networkmanager
  ];
}
