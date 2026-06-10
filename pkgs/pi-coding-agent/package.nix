{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  ripgrep,
}:

let
  version = "0.79.1";
  sources = {
    x86_64-linux = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256:dc19d2b24d15c76951fe440a47a8212cedb437a25696ebf27a55481156de9e86";
    };
    aarch64-linux = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256:a191a0c8d57abf1424c560f53981c2a070f74d2863a47a7958eb16c556c4bc04";
    };
    x86_64-darwin = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256:7db13fe8d3c65823d6efb1f98136bf26289842c2e6a66fc893d20c334c0bbbb3";
    };
    aarch64-darwin = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256:763894f9e560b7eb30f287b2115a52bffae3d6f3453a6d51be525840591f6575";
    };
  };
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "Unsupported system for pi-coding-agent: ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "pi-coding-agent";
  inherit version;

  src = fetchurl {
    inherit (source) url hash;
  };

  sourceRoot = "pi";

  nativeBuildInputs = [
    makeBinaryWrapper
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/pi"
    cp -r . "$out/share/pi"

    makeWrapper "$out/share/pi/pi" "$out/bin/pi" \
      --prefix PATH : "${lib.makeBinPath [ ripgrep ]}"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/pi"
    test -x "$out/share/pi/pi"
  '';

  meta = {
    description = "Coding agent CLI with terminal-first workflows and extensibility";
    homepage = "https://pi.dev/";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
