# Kotlin Language Server - official LSP from JetBrains
# Pre-built binary distribution with bundled JetBrains Runtime
# https://github.com/Kotlin/kotlin-lsp
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  unzip,
  # Linux runtime dependencies for bundled JRE
  alsa-lib,
  fontconfig,
  freetype,
  zlib,
}:

let
  version = "261.13587.0";

  platformInfo = {
    x86_64-linux = {
      platform = "linux-x64";
      sha256 = "dc0ed2e70cb0d61fdabb26aefce8299b7a75c0dcfffb9413715e92caec6e83ec";
    };
    aarch64-linux = {
      platform = "linux-aarch64";
      sha256 = "d1dceb000fe06c5e2c30b95e7f4ab01d05101bd03ed448167feeb544a9f1d651";
    };
    x86_64-darwin = {
      platform = "mac-x64";
      sha256 = "a3972f27229eba2c226060e54baea1c958c82c326dfc971bf53f72a74d0564a3";
    };
    aarch64-darwin = {
      platform = "mac-aarch64";
      sha256 = "d4ea28b22b29cf906fe16d23698a8468f11646a6a66dcb15584f306aaefbee6c";
    };
  };

  info = platformInfo.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "kotlin-lsp";
  inherit version;

  src = fetchurl {
    url = "https://download-cdn.jetbrains.com/kotlin-lsp/${version}/kotlin-lsp-${version}-${info.platform}.zip";
    inherit (info) sha256;
  };

  nativeBuildInputs = [
    unzip
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    fontconfig
    freetype
    zlib
    stdenv.cc.cc.lib
  ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/kotlin-lsp
    cp -r . $out/libexec/kotlin-lsp/

    # Fix permissions on bundled JRE and launch script
    chmod +x $out/libexec/kotlin-lsp/kotlin-lsp.sh
    find $out/libexec/kotlin-lsp/jre -type f -name "*.dylib" -exec chmod +x {} + 2>/dev/null || true
    find $out/libexec/kotlin-lsp/jre -type f \( -name "java" -o -name "javac" -o -name "keytool" \) -exec chmod +x {} +

    mkdir -p $out/bin
    ln -s $out/libexec/kotlin-lsp/kotlin-lsp.sh $out/bin/kotlin-lsp

    runHook postInstall
  '';

  # Don't strip the bundled JRE
  dontStrip = true;

  meta = {
    description = "Official Kotlin Language Server from JetBrains";
    homepage = "https://github.com/Kotlin/kotlin-lsp";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "kotlin-lsp";
  };
}
