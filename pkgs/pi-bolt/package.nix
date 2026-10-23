{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  autoPatchelfHook,
  libxcb,
  ripgrep,
}:

let
  version = "1.0.0";
  tag = "bolt-v${version}";
  baseUrl = "https://github.com/opensec-git/Pi-Bolt/releases/download/${tag}";

  # Each release is a self-contained directory whose executable resolves the
  # bundled themes, HTML export templates and image tools relative to itself,
  # so the whole directory must be installed and only linked from $out/bin.
  # The x86_64-linux default build runs compiled code on AVX2 CPUs (the
  # upstream installer picks it for this hardware); use pi-bolt-linux-x64-baseline
  # on pre-Haswell/Zen1 CPUs.
  sources = {
    x86_64-linux = {
      dir = "pi-bolt-linux-x64";
      url = "${baseUrl}/pi-bolt-linux-x64.tar.xz";
      hash = "sha256-7loQE98/78/NDCSFSfqerlic94a5/PDFu2J8Vdpj4yE=";
    };
    aarch64-linux = {
      dir = "pi-bolt-linux-arm64";
      url = "${baseUrl}/pi-bolt-linux-arm64.tar.xz";
      hash = "sha256-DEmkmMJdscY3B42oQMpVjkWFQo24ZiE8wrJRgp7DzuI=";
    };
    aarch64-darwin = {
      dir = "pi-bolt-darwin-arm64";
      url = "${baseUrl}/pi-bolt-darwin-arm64.tar.xz";
      hash = "sha256-bWC3O+ptvmIcD2TPT5O6tu/pSO983mL/2QCcFIHBFiw=";
    };
  };
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "Unsupported system for pi-bolt: ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "pi-bolt";
  inherit version;

  src = fetchurl {
    inherit (source) url hash;
  };

  sourceRoot = source.dir;

  nativeBuildInputs = [
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    libxcb # dlopened by the bundled linux-platform-x11 native module
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/pi-bolt"
    cp -r . "$out/share/pi-bolt"

    # Link only: the executable locates its bundled resources next to itself.
    makeWrapper "$out/share/pi-bolt/pi" "$out/bin/pi-bolt" \
      --prefix PATH : "${lib.makeBinPath [ ripgrep ]}"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/pi-bolt"
    test -x "$out/share/pi-bolt/pi"
    mkdir -p "$TMPDIR/home"
    HOME="$TMPDIR/home" PI_OFFLINE=1 "$out/bin/pi-bolt" --version | grep "Pi-Bolt ${version}"
  '';

  meta = {
    description = "Pi, the coding agent, compiled ahead of time to one native executable";
    homepage = "https://pi-bolt.opensec.in/";
    changelog = "https://github.com/opensec-git/Pi-Bolt/releases/tag/${tag}";
    license = lib.licenses.mit;
    mainProgram = "pi-bolt";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
