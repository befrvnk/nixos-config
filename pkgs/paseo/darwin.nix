{
  lib,
  stdenvNoCC,
  fetchzip,
  makeBinaryWrapper,
}:

let
  sources = {
    aarch64-darwin = fetchzip {
      url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-${version}-arm64.zip";
      hash = "sha256-dK2lTQbJGB0YpzfbmBTpxk9FEOQgxZHONSQNnfNdRpI=";
    };
    x86_64-darwin = fetchzip {
      url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-${version}-x64.zip";
      hash = "sha256-+zulgacAmStiwNwTo5aRkcMWsFyY9+YKJ9vuf7zL2KM=";
    };
  };

  version = "0.1.64";
in
stdenvNoCC.mkDerivation {
  pname = "paseo";
  inherit version;

  src = sources.${stdenvNoCC.hostPlatform.system};

  dontUnpack = true;
  dontPatchShebangs = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications/Paseo.app" "$out/bin"
    cp -R "$src"/. "$out/Applications/Paseo.app"

    makeBinaryWrapper \
      "$out/Applications/Paseo.app/Contents/MacOS/Paseo" \
      "$out/bin/paseo-desktop"

    ln -s "$out/Applications/Paseo.app/Contents/Resources/bin/paseo" "$out/bin/paseo"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/paseo"
    test -x "$out/bin/paseo-desktop"
    test -x "$out/Applications/Paseo.app/Contents/MacOS/Paseo"
    test -f "$out/Applications/Paseo.app/Contents/Resources/app.asar"
  '';

  meta = {
    description = "Desktop and CLI interface for Claude Code, Codex, and OpenCode agents";
    homepage = "https://github.com/getpaseo/paseo";
    changelog = "https://github.com/getpaseo/paseo/releases/tag/v${version}";
    license = lib.licenses.agpl3Plus;
    mainProgram = "paseo-desktop";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
