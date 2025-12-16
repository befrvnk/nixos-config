{ pkgs }:

let
  pname = "elecwhat";
  version = "1.12.3";

  src = pkgs.fetchurl {
    url = "https://github.com/piec/elecwhat/releases/download/v${version}/elecwhat-${version}.AppImage";
    hash = "sha256-Wq8O8PSl/YCHVBS8FUOVEIUMkGthrc6zW+RE2Jl/4WU=";
  };

  appimageContents = pkgs.appimageTools.extractType2 { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/elecwhat.desktop $out/share/applications/elecwhat.desktop
    install -m 444 -D ${appimageContents}/elecwhat.png $out/share/icons/hicolor/512x512/apps/elecwhat.png
    substituteInPlace $out/share/applications/elecwhat.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=elecwhat'
  '';

  meta = with pkgs.lib; {
    description = "Simple desktop WhatsApp client for Linux";
    homepage = "https://github.com/piec/elecwhat";
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "elecwhat";
  };
}
