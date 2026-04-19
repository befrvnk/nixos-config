{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
}:

stdenvNoCC.mkDerivation rec {
  pname = "openchamber";
  version = "1.9.6";

  appName = "OpenChamber.app";
  executable = "openchamber-desktop";

  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber.app-darwin-aarch64.tar.gz";
    hash = "sha256-B6RFT0zbVQ6Em6dMSijgECQQTJ/63wIzmAD8ZKID2dk=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications $out/bin
    cp -r ${appName} $out/Applications/
    makeBinaryWrapper \
      "$out/Applications/${appName}/Contents/MacOS/${executable}" \
      "$out/bin/openchamber"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/openchamber"
    test -x "$out/Applications/${appName}/Contents/MacOS/${executable}"
  '';

  meta = {
    description = "Desktop and web interface for the OpenCode AI agent";
    homepage = "https://github.com/openchamber/openchamber";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "openchamber";
  };
}
