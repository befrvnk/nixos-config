{
  lib,
  stdenvNoCC,
  fetchzip,
  makeBinaryWrapper,
}:

stdenvNoCC.mkDerivation rec {
  pname = "openchamber";
  version = "1.13.3";

  appName = "OpenChamber.app";
  executable = "OpenChamber";

  src = fetchzip {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber-${version}-mac-arm64.zip";
    hash = "sha256-xVqsKBb7dYkZ1tpRqDi1qCi1m6OEA7IGNStV9+Jnuqc=";
    stripRoot = false;
  };

  dontUnpack = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications $out/bin
    cp -r "$src/${appName}" $out/Applications/
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
