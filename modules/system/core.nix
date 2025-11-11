{ ... }:

{
  boot.initrd.systemd.enable = true;
  security.tpm2.enable = true;

  # Let the Framework hardware module handle kernel selection
  # boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";

  i18n = {
    defaultLocale = "en_US.UTF-8";
  };

  programs.zsh.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Configure systemd-logind for proper lid handling
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "suspend";
    IdleAction = "ignore";
  };

  system.stateVersion = "25.05";
}
