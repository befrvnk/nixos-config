{
  lib,
  stdenvNoCC,
  fetchzip,
  makeBinaryWrapper,
}:

let
  sources = {
    aarch64-darwin = fetchzip {
      url = "https://github.com/stablyai/orca/releases/download/v${version}/Orca-${version}-arm64-mac.zip";
      hash = "sha256-CYgdyy4T1zK3NG1d5PLrz5UjrFiV7gmeCCcQNAVEIRA=";
    };
    x86_64-darwin = fetchzip {
      url = "https://github.com/stablyai/orca/releases/download/v${version}/Orca-${version}-mac.zip";
      hash = "sha256-k7vEDZ0jHc5y4I8Y0KdywEHkP3bL8rQD0zIBL05EdZ0=";
    };
  };

  version = "1.3.24";
in
stdenvNoCC.mkDerivation {
  pname = "orca-ai";
  inherit version;

  src = sources.${stdenvNoCC.hostPlatform.system};

  dontUnpack = true;
  dontPatchShebangs = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications/Orca.app" "$out/bin"
    cp -R "$src"/. "$out/Applications/Orca.app"

    makeBinaryWrapper \
      "$out/Applications/Orca.app/Contents/MacOS/Orca" \
      "$out/bin/orca-ai"

    ln -s "$out/Applications/Orca.app/Contents/Resources/bin/orca" "$out/bin/orca-ai-cli"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/orca-ai"
    test -x "$out/bin/orca-ai-cli"
    test -x "$out/Applications/Orca.app/Contents/MacOS/Orca"
    test -f "$out/Applications/Orca.app/Contents/Resources/app.asar"
  '';

  meta = {
    description = "Next-gen IDE for building with coding agents";
    homepage = "https://github.com/stablyai/orca";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "orca-ai";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
