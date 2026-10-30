{
  appimageTools,
  asar,
  fetchurl,
  fetchzip,
  lib,
  makeBinaryWrapper,
  runCommand,
  stdenv,
  stdenvNoCC,
  symlinkJoin,
  writeShellScriptBin,
}:

let
  pname = "openchamber";
  version = "2.5.3";
  appName = "OpenChamber.app";
  executable = "OpenChamber";
  darwinHash = "sha256-gd8EWcYuP5iGE3g1exgX1Ry4Il25sUQw1AUN3tkKcxc=";
  linuxX86Hash = "sha256-wDSorfUq9bxQ+Z3OmU1wFZdBB00MQmb0VrcPWbyB3jI=";
  linuxArm64Hash = "sha256-jt500GfMDI/N8WEJJxRGy1UBes90X6a3uLfqappKH54=";

  meta = {
    description = "Desktop and web interface for the OpenCode AI agent";
    homepage = "https://github.com/openchamber/openchamber";
    changelog = "https://github.com/openchamber/openchamber/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
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
    linuxArch = if stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64";
    linuxHash = if stdenv.hostPlatform.isAarch64 then linuxArm64Hash else linuxX86Hash;
    src = fetchurl {
      url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber-${version}-linux-${linuxArch}.AppImage";
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

    # The desktop bundle embeds @openchamber/web, including its CLI and the
    # native modules built for the bundled Electron runtime. Extract that asar
    # so the same binary can run the headless server via ELECTRON_RUN_AS_NODE.
    webAsar =
      runCommand "openchamber-web-asar-${version}"
        {
          nativeBuildInputs = [ asar ];
        }
        ''
          mkdir -p $out
          asar extract ${appimageContents}/resources/app.asar $out
          cp -a ${appimageContents}/resources/app.asar.unpacked/. $out/
        '';

    webWrapper = writeShellScriptBin "openchamber-web" ''
      export ELECTRON_RUN_AS_NODE=1
      exec ${unwrapped}/bin/${pname} ${webAsar}/node_modules/@openchamber/web/bin/cli.js "$@"
    '';

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
    paths = [
      unwrapped
      webWrapper
    ];
    nativeBuildInputs = [ makeBinaryWrapper ];
    postBuild = ''
      wrapProgram $out/bin/${pname} \
        --set OPENCODE_DISABLE_CLAUDE_CODE true

      # Without these the app is invisible to desktop launchers.
      test -e $out/share/applications/${pname}.desktop
      test -e $out/share/icons/hicolor/512x512/apps/${pname}.png
      test -x $out/bin/openchamber-web
    '';
  }
