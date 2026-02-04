{ pkgs, ... }:

let
  audioIdleInhibitScript = pkgs.writeShellScript "audio-idle-inhibit" ''
    export PATH="${pkgs.wireplumber}/bin:${pkgs.systemd}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:$PATH"

    ${builtins.readFile ./audio-idle-inhibit.sh}
  '';
in
{
  # Prevent idle/suspend while audio is actually playing
  # Uses wpctl to detect actual audio activity (not just connected streams)
  # This solves the clamshell mode issue where browser streams stay "connected"
  systemd.user.services.audio-idle-inhibit = {
    Unit = {
      Description = "Prevent idle/suspend when audio is playing";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${audioIdleInhibitScript}";
      Restart = "always";
      RestartSec = "10";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
