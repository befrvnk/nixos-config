{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
}:

stdenvNoCC.mkDerivation rec {
  pname = "openchamber";
  version = "1.11.2";

  appName = "OpenChamber.app";
  executable = "openchamber-desktop";

  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber.app-darwin-aarch64.tar.gz";
    hash = "sha256-k1BqlkVNzHLABS7OqwPgMP5OPpay8nDTsqNSSQmrXSg=";
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
