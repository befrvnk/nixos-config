{ pkgs, ... }:

{
  boot.initrd.systemd.enable = true;
  security.tpm2.enable = true;

  # Allow passwordless sudo for CPU governor switching helper
  # Allows frank user to run set-governor-helper without password
  # Also allows passwordless tee to platform_profile for power profile switching
  security.sudo.extraConfig = ''
    frank ALL=(root) NOPASSWD: /home/frank/.nix-profile/bin/set-governor-helper*
    frank ALL=(root) NOPASSWD: /nix/store/*/bin/set-governor-helper*
    frank ALL=(root) NOPASSWD: /run/current-system/sw/bin/tee /sys/firmware/acpi/platform_profile
  '';

  # Let the Framework hardware module handle kernel selection
  # boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";

  i18n = {
    defaultLocale = "en_US.UTF-8";
  };

  programs.zsh.enable = true;

  # Enable nix-ld for running dynamically linked executables
  programs.nix-ld = {
    enable = true;
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Allow the user to configure binary caches (needed for devenv)
    trusted-users = [
      "root"
      "frank"
    ];
  };

  # Configure systemd-logind for proper lid handling
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "suspend";
    IdleAction = "ignore";
  };

  # Enable USB wake only for keyboards
  services.udev.extraRules = ''
    # First, disable wake for all USB devices by default
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"

    # Then enable wake only for external keyboard
    # NuPhy Air75 V3
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="19f5", ATTRS{idProduct}=="1028", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"
  '';

  system.stateVersion = "25.05";
}
