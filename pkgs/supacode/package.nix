{
  lib,
  stdenvNoCC,
  fetchzip,
  gh,
  makeBinaryWrapper,
}:

let
  githubCliPath = lib.makeBinPath [ gh ];
in
stdenvNoCC.mkDerivation rec {
  pname = "supacode";
  version = "0.9.2";

  src = fetchzip {
    url = "https://github.com/supabitapp/supacode/releases/download/v${version}/supacode.app.zip";
    hash = "sha256-R4dOzMAB+EMDRjp+lFMb/WiVSA8RN5YmRAahi3WNPNs=";
    stripRoot = false;
  };

  dontUnpack = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -r "$src/supacode.app" "$out/Applications/"
    chmod -R u+w "$out/Applications/supacode.app"

    app_executable="$out/Applications/supacode.app/Contents/MacOS/supacode"
    mv "$app_executable" "$app_executable-unwrapped"
    /usr/bin/codesign --force --sign - "$app_executable-unwrapped"

    # Supacode resolves and runs gh through a POSIX/zsh-style login-shell
    # wrapper. That wrapper currently fails when SHELL points at Nushell, so
    # set a POSIX shell for Supacode's own subprocesses while keeping the user's
    # interactive shell unchanged. Also put nixpkgs gh directly on PATH so GUI
    # launches do not depend on launchd inheriting the Home Manager profile.
    makeBinaryWrapper \
      "$app_executable-unwrapped" \
      "$app_executable" \
      --set SHELL /bin/zsh \
      --prefix PATH : "${githubCliPath}"

    makeBinaryWrapper \
      "$app_executable" \
      "$out/bin/supacode" \
      --set SHELL /bin/zsh \
      --prefix PATH : "${githubCliPath}"

    # Drop the upstream bundle signature after replacing the executable wrapper;
    # otherwise the resource seal no longer matches. The wrapper and original
    # Mach-O executable remain individually signed/ad-hoc signed.
    rm -rf "$out/Applications/supacode.app/Contents/_CodeSignature"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/supacode"
    test -x "$out/Applications/supacode.app/Contents/MacOS/supacode"
    test -x "$out/Applications/supacode.app/Contents/MacOS/supacode-unwrapped"
  '';

  meta = {
    description = "Native macOS coding app from Supabit";
    homepage = "https://github.com/supabitapp/supacode";
    changelog = "https://github.com/supabitapp/supacode/releases/tag/v${version}";
    license = lib.licenses.unfree;
    mainProgram = "supacode";
    platforms = [
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
