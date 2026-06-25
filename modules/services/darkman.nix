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

    # darkman runs Home Manager Stylix specialisations from its mode hooks.
    # If switch-to-configuration restarts darkman before home-manager-frank.service,
    # those hooks race with the normal Home Manager activation and can make the
    # switch fail in linkGeneration. Keep the daemon running across rebuilds; the
    # Home Manager activation hook re-applies the current mode after linking.
    restartIfChanged = false;
    stopIfChanged = false;

    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkgs.darkman}/bin/darkman run";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
