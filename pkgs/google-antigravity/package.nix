{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  unzip,
}:

let
  version = "2.0.1";
  releaseId = "6566078776737792";

  sources = {
    aarch64-darwin = {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-hub/${version}-${releaseId}/darwin-arm/Antigravity.zip";
      hash = "sha256-4/hh57p2wSvDCed1ACsybV5Is0CFN6RwkUQnPo+OtXM=";
    };
    x86_64-darwin = {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-hub/${version}-${releaseId}/darwin-x64/Antigravity.zip";
      hash = "sha256-OcmjQDUJTH3uOP9GEBRvuY5YrDE1URa+6hGy/w+CL6k=";
    };
  };

  source = sources.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "google-antigravity";
  inherit version;

  src = fetchurl source;

  dontUnpack = true;
  dontPatchShebangs = true;

  nativeBuildInputs = [
    makeBinaryWrapper
    unzip
  ];

  installPhase = ''
    runHook preInstall

    app_src="$TMPDIR/antigravity"
    mkdir -p "$app_src" "$out/Applications" "$out/bin"
    unzip -q "$src" -d "$app_src"

    cp -R "$app_src/Antigravity.app" "$out/Applications/"

    makeBinaryWrapper \
      "$out/Applications/Antigravity.app/Contents/MacOS/Antigravity" \
      "$out/bin/antigravity"

    ln -s "$out/bin/antigravity" "$out/bin/agy"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -d "$out/Applications/Antigravity.app"
    test -x "$out/Applications/Antigravity.app/Contents/MacOS/Antigravity"
    test -x "$out/bin/antigravity"
    test -L "$out/bin/agy"
  '';

  meta = {
    description = "AI coding agent IDE from Google";
    homepage = "https://antigravity.google/";
    license = lib.licenses.unfree;
    mainProgram = "antigravity";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
