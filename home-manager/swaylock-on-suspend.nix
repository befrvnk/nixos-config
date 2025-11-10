{ pkgs, ... }:

{
  # Automatically lock the screen before suspend/sleep
  systemd.user.services.swaylock-on-suspend = {
    Unit = {
      Description = "Lock screen before suspend";
      Before = [ "sleep.target" ];
    };
    Service = {
      Type = "forking";
      Environment = "PATH=${pkgs.swaylock}/bin";
      ExecStart = "${pkgs.swaylock}/bin/swaylock -f";
    };
    Install = {
      WantedBy = [ "sleep.target" ];
    };
  };
}
