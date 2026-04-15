{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
}:

stdenvNoCC.mkDerivation rec {
  pname = "openchamber";
  version = "1.9.5";

  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber.app-darwin-aarch64.tar.gz";
    hash = "sha256-fz7fl3LQ1/3dGwsHFwEorpCglPLxs2gWIlo4Fy4NIfs=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications $out/bin
    cp -r OpenChamber.app $out/Applications/
    makeBinaryWrapper \
      "$out/Applications/OpenChamber.app/Contents/MacOS/OpenChamber" \
      "$out/bin/openchamber"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/openchamber"
    test -x "$out/Applications/OpenChamber.app/Contents/MacOS/OpenChamber"
  '';

  meta = {
    description = "Desktop and web interface for the OpenCode AI agent";
    homepage = "https://github.com/openchamber/openchamber";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "openchamber";
  };
}
