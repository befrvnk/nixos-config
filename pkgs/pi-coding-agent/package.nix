{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  ripgrep,
}:

let
  version = "0.80.3";
  sources = {
    x86_64-linux = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256:e74a34ac2505556164144d8e39a64d6d5276f092166dad914319edc30c48abee";
    };
    aarch64-linux = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256:c544ab2a0953a9bda358cab9bc328b1ef6892d4a824d8693880977e4b23c6168";
    };
    x86_64-darwin = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256:c1e007bd68cf3779f09476f9c06de5fc93a00733d4ae34a36a96180156ff1e7f";
    };
    aarch64-darwin = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256:072789f5f5571198bd2d856f1ac4bbc980eecce1d02e7d0acf896e2387e3ee8f";
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
