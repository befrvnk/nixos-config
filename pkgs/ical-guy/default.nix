{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation rec {
  pname = "ical-guy";
  version = "0.15.1";

  src = fetchurl {
    url = "https://github.com/itspriddle/ical-guy/releases/download/v${version}/ical-guy-v${version}-macos-universal.tar.gz";
    sha256 = "ce06524c45ec46d365dd106c30767642add17b438bdc50622cdc7f0111312c56";
  };

  sourceRoot = ".";
  dontStrip = true;
  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 ical-guy "$out/bin/ical-guy"
    runHook postInstall
  '';

  meta = {
    description = "Read macOS Calendar events through EventKit with JSON output";
    homepage = "https://github.com/itspriddle/ical-guy";
    license = lib.licenses.mit;
    mainProgram = "ical-guy";
    platforms = lib.platforms.darwin;
  };
}
