{ pkgs, ... }:
let
  agendaExtension =
    pkgs.runCommand "asyar-agenda-extension"
      {
        nativeBuildInputs = [
          pkgs.esbuild
          pkgs.typescript
          pkgs.tsx
        ];
      }
      ''
        mkdir -p $out
        cp -r ${./extensions/agenda}/* $out/
        chmod -R u+w $out
        cd $out
        tsc --noEmit --project tsconfig.json
        tsx src/agenda.test.ts
        esbuild src/index.ts --bundle --target=es2022 --format=esm --minify --outfile=$out/view.js
        rm -rf src tsconfig.json
      '';
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
