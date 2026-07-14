{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  ripgrep,
}:

let
  version = "0.80.7";
  sources = {
    x86_64-linux = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256:c5f5a9a77a38e68fcb089dd4e3505abb64c98d19595b55818c961be779889719";
    };
    aarch64-linux = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256:bd8bf49b36da00faf41b95c832daf538522816c09506191c900be606868bb531";
    };
    x86_64-darwin = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256:3e71ac3aa4ba6cd92f7f8c704e06282b4413842877e7670b2dce3b1bf422318d";
    };
    aarch64-darwin = {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256:0f15771ef76ecd69b03e28fecf0c512593ff6e2477acf39e35bc2c8a4056d1e3";
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
    HOME="$TMPDIR/home" PI_OFFLINE=1 "$out/bin/pi" --version
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
