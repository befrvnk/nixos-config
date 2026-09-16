{ pkgs, ... }:
let
  agendaExtension = ./extensions/agenda;
  agendaDir = "org.asyar.app/extensions/org.asyar.agenda";

  themeExtension = ./extensions/theme-toggle;
  themeDir = "org.asyar.app/extensions/org.asyar.theme-toggle";

  devExtensions = builtins.toJSON {
    "org.asyar.agenda" = "${agendaExtension}";
    "org.asyar.theme-toggle" = "${themeExtension}";
  };
in
{
  xdg.dataFile = pkgs.lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    ${agendaDir}.source = agendaExtension;
    ${themeDir}.source = themeExtension;
    "org.asyar.app/dev_extensions.json".text = devExtensions;
  };

  home.file = pkgs.lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    "Library/Application Support/${agendaDir}".source = agendaExtension;
    "Library/Application Support/${themeDir}".source = themeExtension;
    "Library/Application Support/org.asyar.app/dev_extensions.json".text = devExtensions;
  };
}
