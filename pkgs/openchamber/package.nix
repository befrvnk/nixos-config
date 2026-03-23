{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "openchamber";
  version = "1.9.1";

  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber.app-darwin-aarch64.tar.gz";
    hash = "sha256-mwvs+ZwJ5/sUUoiTlqvQRvuW+D4bxO9wXBJfZYK7Fy8=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -r OpenChamber.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Desktop and web interface for the OpenCode AI agent";
    homepage = "https://github.com/openchamber/openchamber";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "OpenChamber";
  };
}
