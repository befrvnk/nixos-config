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
  version = "2.5.2";
  appName = "OpenChamber.app";
  executable = "OpenChamber";
  darwinHash = "sha256-p/BnHE3RIsv7Q32hsmVGr2tEoyMUtlO3NiQDHha/V9U=";
  linuxHash = "sha256-6VgPKo5ctn5ppCRtFjuwnH8vKFhQS9cIbU+iBlVKWHg=";

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

    # The AppImage ships the freedesktop entry and icon that launchers such as
    # Vicinae index. Extract them so the wrapped package keeps them visible.
    appimageContents = appimageTools.extract {
      inherit
        pname
        version
        src
        ;
    };

    unwrapped = appimageTools.wrapType2 {
      inherit
        pname
        version
        src
        meta
        ;

      extraInstallCommands = ''
        install -m 444 -D ${appimageContents}/openchamber.desktop $out/share/applications/openchamber.desktop
        install -m 444 -D ${appimageContents}/openchamber.png $out/share/icons/hicolor/512x512/apps/openchamber.png
        substituteInPlace $out/share/applications/openchamber.desktop \
          --replace-fail 'Exec=AppRun' 'Exec=${pname}'
      '';
    };
  in
  symlinkJoin {
    inherit pname version meta;
    paths = [ unwrapped ];
    nativeBuildInputs = [ makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/${pname} \
        --set OPENCODE_DISABLE_CLAUDE_CODE true

      # Without these the app is invisible to desktop launchers.
      test -e $out/share/applications/${pname}.desktop
      test -e $out/share/icons/hicolor/512x512/apps/${pname}.png
    '';
  }
