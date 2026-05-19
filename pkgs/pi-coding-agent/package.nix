{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  ripgrep,
}:

let
  version = "0.75.3";
  sources = {
    x86_64-linux = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256:86ef48db5ba98a784acf1dbce1bd6d5fd5b6bee3ee2ef449e0811a82d1ba78c3";
    };
    aarch64-linux = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256:341389b59ad4a54a268114c4e2b4e65e014f97a581fd14ea722c20b33897eecd";
    };
    x86_64-darwin = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256:2432cf0b6a984d3fb6d029b5fd650862a42cce921b25bd5b6d17ce9afcc3e69a";
    };
    aarch64-darwin = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256:2d16668d626805ea73d430b178b22f5341152c7c13544c46f89d68058e0bbf81";
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
