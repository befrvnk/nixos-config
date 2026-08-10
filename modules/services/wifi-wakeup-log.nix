{
  lib,
  pkgs,
  hostConfig,
  ...
}:

let
  wifiIf = hostConfig.wifiInterface or null;

  wifiWakeupScript = pkgs.writeShellScript "wifi-wakeup-log" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.iproute2
        pkgs.iputils
        pkgs.iw
        pkgs.pciutils
      ]
    }"
    ${builtins.readFile ./wifi-wakeup-log.sh}
  '';
in
{
  # Capture WiFi state before suspend and after resume. Aims to pinpoint why
  # internet is sometimes very slow after waking, even though the wifi link
  # looks healthy. See docs/wifi-wakeup-log.md.
  #
  # Hooked via the systemd sleep.target mechanism (same pattern NixOS uses for
  # powerManagement.resumeCommands): a oneshot pulled in by sleep.target whose
  # `script` runs before sleep and whose `preStop` runs after resume.
  systemd.services.wifi-wakeup-log = lib.mkIf (wifiIf != null) {
    description = "Log WiFi state before suspend and after resume to diagnose slow wake";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # Runs just before sleep (state is fresh and the link is up).
    script = ''
      ${wifiWakeupScript} "${wifiIf}" suspend
    '';

    # Runs after resume, when the unit is stopped as the sleep transaction ends.
    preStop = ''
      ${wifiWakeupScript} "${wifiIf}" resume
    '';
  };
}
