{ pkgs, ... }:

{
  # Enable darkman as a system service
  environment.systemPackages = [ pkgs.darkman ];

  # Create systemd service for darkman
  systemd.user.services.darkman = {
    description = "Framework for dark-mode and light-mode transitions";
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkgs.darkman}/bin/darkman run";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
