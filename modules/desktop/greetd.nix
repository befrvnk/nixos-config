{ pkgs, ... }:

{
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd ${pkgs.niri}/bin/niri-session";
        user = "greeter";
      };
    };
  };

  # Suppress greetd logs in systemd journal
  systemd.services.greetd.serviceConfig = {
    StandardInput = "tty";
    StandardOutput = "tty";
    # Without this errors will spam on screen
    StandardError = "journal";
  };

  # Auto-unlock gnome-keyring on login
  security.pam.services.greetd.enableGnomeKeyring = true;
}
