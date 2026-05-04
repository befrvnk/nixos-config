{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
  makeBinaryWrapper,
}:

stdenvNoCC.mkDerivation rec {
  pname = "aizen";
  version = "1.0.81";

  src = fetchurl {
    url = "https://r2.aizen.win/Aizen-${version}.dmg";
    hash = "sha256-OktlSED8GYT/jEk07jdqCbDab3ZWXoDwijT6uOs4z90=";
  };

  nativeBuildInputs = [
    undmg
    makeBinaryWrapper
  ];

  sourceRoot = ".";
  dontPatchShebangs = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -R "Aizen.app" "$out/Applications/"

    ln -s "$out/Applications/Aizen.app/Contents/Resources/cli/aizen-cli" "$out/bin/aizen"
    ln -s "$out/Applications/Aizen.app/Contents/Resources/cli/aizen-cli" "$out/bin/aizen-cli"

    makeBinaryWrapper \
      "$out/Applications/Aizen.app/Contents/MacOS/Aizen" \
      "$out/bin/aizen-app"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/aizen"
    test -x "$out/bin/aizen-cli"
    test -x "$out/bin/aizen-app"
    test -x "$out/Applications/Aizen.app/Contents/MacOS/Aizen"
    test -x "$out/Applications/Aizen.app/Contents/Resources/cli/aizen-cli"
  '';

  meta = {
    description = "macOS workspace for parallel development with AI coding agents";
    homepage = "https://aizen.win/";
    changelog = "https://github.com/vivy-company/aizen/releases/tag/v${version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "aizen";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
