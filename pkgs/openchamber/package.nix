{
  appimageTools,
  fetchurl,
  fetchzip,
  lib,
  makeBinaryWrapper,
  stdenv,
  stdenvNoCC,
  symlinkJoin,
}:

let
  pname = "openchamber";
  version = "1.20.0";
  appName = "OpenChamber.app";
  executable = "OpenChamber";
  darwinHash = "sha256-MAtWqnf6pkv7lvdCabLrSSZukJL+YjjOZgGi08/4/nA=";
  linuxHash = "sha256-ONMae8MYlwEtF1ffOmSV/93gGC2CdHdlwKf6DDmrROk=";

  meta = {
    description = "Desktop and web interface for the OpenCode AI agent";
    homepage = "https://github.com/openchamber/openchamber";
    changelog = "https://github.com/openchamber/openchamber/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
in
if stdenv.hostPlatform.isDarwin then
  stdenvNoCC.mkDerivation {
    inherit pname version meta;

    src = fetchzip {
      url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber-${version}-mac-arm64.zip";
      hash = darwinHash;
      stripRoot = false;
    };

    dontUnpack = true;

    nativeBuildInputs = [ makeBinaryWrapper ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/Applications" "$out/bin"
      cp -r "$src/${appName}" "$out/Applications/"

      # The bundle's executable is covered by the upstream macOS code signature.
      # Wrapping it in place invalidates that signature and prevents LaunchServices
      # from starting the application. Keep the bundle unchanged; only wrap the
      # command-line entry point outside it.
      makeBinaryWrapper "$out/Applications/${appName}/Contents/MacOS/${executable}" "$out/bin/${pname}" \
        --set OPENCODE_DISABLE_CLAUDE_CODE true

      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      test -x "$out/bin/${pname}"
      test -x "$out/Applications/${appName}/Contents/MacOS/${executable}"
    '';
  }
else
  let
    src = fetchurl {
      url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber-${version}-linux-x86_64.AppImage";
      hash = linuxHash;
    };

    unwrapped = appimageTools.wrapType2 {
      inherit
        pname
        version
        src
        meta
        ;
    };
  in
  symlinkJoin {
    inherit pname version meta;
    paths = [ unwrapped ];
    nativeBuildInputs = [ makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/${pname} \
        --set OPENCODE_DISABLE_CLAUDE_CODE true
    '';
  }
