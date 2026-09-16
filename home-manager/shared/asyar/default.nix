{ pkgs, ... }:
let
  agendaExtension = ./extensions/agenda;
  agendaDir = "org.asyar.app/extensions/org.asyar.agenda";
in
{
  # Linux: ~/.local/share/org.asyar.app/
  xdg.dataFile.${agendaDir} = pkgs.lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    source = agendaExtension;
  };
  xdg.dataFile."org.asyar.app/dev_extensions.json" = pkgs.lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    text = builtins.toJSON {
      "org.asyar.agenda" = "${agendaExtension}";
    };
  };

  # macOS: ~/Library/Application Support/org.asyar.app/
  home.file."Library/Application Support/${agendaDir}" =
    pkgs.lib.mkIf pkgs.stdenv.hostPlatform.isDarwin
      {
        source = agendaExtension;
      };
  home.file."Library/Application Support/org.asyar.app/dev_extensions.json" =
    pkgs.lib.mkIf pkgs.stdenv.hostPlatform.isDarwin
      {
        text = builtins.toJSON {
          "org.asyar.agenda" = "${agendaExtension}";
        };
      };
}
