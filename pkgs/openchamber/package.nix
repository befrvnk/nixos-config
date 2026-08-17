{
  lib,
  stdenvNoCC,
  fetchzip,
  makeBinaryWrapper,
}:

stdenvNoCC.mkDerivation rec {
  pname = "openchamber";
  version = "1.18.4";

  appName = "OpenChamber.app";
  executable = "OpenChamber";

  src = fetchzip {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber-${version}-mac-arm64.zip";
    hash = "sha256-tb3xPr4gV0Fe+J8lZ6ala5wf2T9WyGr9pOgnsjXH0FM=";
    stripRoot = false;
  };

  dontUnpack = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -r "$src/${appName}" "$out/Applications/"
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
    changelog = "https://github.com/openchamber/openchamber/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "openchamber";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
