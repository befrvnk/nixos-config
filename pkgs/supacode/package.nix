{
  lib,
  stdenvNoCC,
  fetchzip,
  makeBinaryWrapper,
}:

stdenvNoCC.mkDerivation rec {
  pname = "supacode";
  version = "0.8.5";

  src = fetchzip {
    url = "https://github.com/supabitapp/supacode/releases/download/v${version}/supacode.app.zip";
    hash = "sha256-lnCbhP2Ns3icEkeOemGbutq2YOwurOqZqU+o8Q+3CpM=";
    stripRoot = false;
  };

  dontUnpack = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -r "$src/supacode.app" "$out/Applications/"

    makeBinaryWrapper \
      "$out/Applications/supacode.app/Contents/MacOS/supacode" \
      "$out/bin/supacode"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/supacode"
    test -x "$out/Applications/supacode.app/Contents/MacOS/supacode"
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
