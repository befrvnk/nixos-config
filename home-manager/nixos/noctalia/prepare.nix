{
  config,
  lib,
  pkgs,
  ...
}:
let
  # A single manifest keeps one python process on the activation critical
  # path instead of one per app: this entry runs between linkGeneration and
  # writeBoundary, i.e. inside the boot-blocking Home Manager unit.
  manifest = pkgs.writeText "noctalia-prepare-outputs.json" (
    builtins.toJSON config.noctalia.prepareOutputs
  );
in
{
  options.noctalia.prepareOutputs = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          theme = lib.mkOption {
            type = lib.types.str;
            description = "Writable runtime theme output that must exist before linkGeneration.";
          };
          backup = lib.mkOption {
            type = lib.types.str;
            description = "Path the original file is copied to once, before any rewrite.";
          };
          placeholder = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Seed content for a missing output; null keeps the preparer's own default.";
          };
        };
      }
    );
    default = [ ];
    description = ''
      Writable Noctalia theme outputs seeded once per Home Manager activation.
      Apps contribute their output here instead of defining their own
      `home.activation` entry, so activation cost does not grow per app.
    '';
  };

  config.home.activation.prepareNoctaliaThemeOutputs =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          --manifest ${manifest}
      '';
}
