{ lib, pkgs }:
{
  mkPathWrappedScript =
    {
      name,
      packages,
      script,
    }:
    pkgs.writeShellScript name ''
      export PATH="${lib.makeBinPath packages}:$PATH"
      ${builtins.readFile script}
    '';

  mkGraphicalUserService =
    {
      description,
      execStart,
      after ? [ ],
      requires ? [ ],
      partOf ? [ "graphical-session.target" ],
      restartSec ? "5",
      unit ? { },
      service ? { },
      wantedBy ? [ "graphical-session.target" ],
    }:
    {
      Unit = {
        Description = description;
        After = [ "graphical-session.target" ] ++ after;
        PartOf = partOf;
        Requires = requires;
      }
      // unit;

      Service = {
        Type = "simple";
        ExecStart = execStart;
        Restart = "always";
        RestartSec = restartSec;
      }
      // service;

      Install.WantedBy = wantedBy;
    };
}
