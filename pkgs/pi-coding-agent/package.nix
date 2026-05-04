{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  ripgrep,
}:

let
  version = "0.72.1";
  sources = {
    x86_64-linux = {
      url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256:00fab8b1f194140a8c9dbd2614b38e99726cd5dde3b5b2d607bd5daa6f851d40";
    };
    aarch64-linux = {
      url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256:79c4c585765cfda01624bde1ef529c6e55081bcdde3058e64ebe8fdfdc14b4a8";
    };
    x86_64-darwin = {
      url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256:59aa55b483cd42d78079f1a3b6244f8baebb63ea4dec8208d72eb0bf2df69aa2";
    };
    aarch64-darwin = {
      url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256:40b2f027fc0f581317072921bf2e7ddfec871c3a4e94b73c39d73fc2abc5e517";
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
    changelog = "https://github.com/badlogic/pi-mono/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
