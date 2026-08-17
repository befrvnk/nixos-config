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
  version = "1.18.4";
  appName = "OpenChamber.app";
  executable = "OpenChamber";
  darwinHash = "sha256-tb3xPr4gV0Fe+J8lZ6ala5wf2T9WyGr9pOgnsjXH0FM=";
  linuxHash = "sha256-ERThxACGbfFlFFqikQZIcZPF1ChpYJrFBBaYwYDG4DI=";

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
      chmod -R u+w "$out/Applications/${appName}"

      appExecutable="$out/Applications/${appName}/Contents/MacOS/${executable}"
      mv "$appExecutable" "$appExecutable-unwrapped"
      makeBinaryWrapper "$appExecutable-unwrapped" "$appExecutable" \
        --set OPENCODE_DISABLE_CLAUDE_CODE true
      ln -s "$appExecutable" "$out/bin/${pname}"

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
