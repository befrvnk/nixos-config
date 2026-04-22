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
  libX11,
  libXext,
  libXi,
  libXrender,
  libXtst,
  wayland,
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
    libX11
    libXext
    libXi
    libXrender
    libXtst
    stdenv.cc.cc.lib
    wayland
    zlib
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
        cat > $out/bin/kotlin-lsp <<'EOF'
    #!${stdenv.shell}
    set -eu

    DIR="@out@/libexec/kotlin-lsp"

    if [ ! -d "$DIR/lib" ]; then
      echo >&2 "The 'lib' directory does not exist."
      exit 1
    fi

    ${
      if stdenv.hostPlatform.isDarwin then
        ''
          LOCAL_JRE_PATH="$DIR/jre/Contents/Home"
        ''
      else
        ''
          LOCAL_JRE_PATH="$DIR/jre"
        ''
    }

    if [ -d "$LOCAL_JRE_PATH" ] && [ -f "$LOCAL_JRE_PATH/bin/java" ]; then
      JAVA_BIN="$LOCAL_JRE_PATH/bin/java"
    else
      echo >&2 "'java' was not found at $LOCAL_JRE_PATH, installation corrupted"
      exit 1
    fi

    exec "$JAVA_BIN" \
      --add-opens java.base/java.io=ALL-UNNAMED \
      --add-opens java.base/java.lang=ALL-UNNAMED \
      --add-opens java.base/java.lang.ref=ALL-UNNAMED \
      --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
      --add-opens java.base/java.net=ALL-UNNAMED \
      --add-opens java.base/java.nio=ALL-UNNAMED \
      --add-opens java.base/java.nio.charset=ALL-UNNAMED \
      --add-opens java.base/java.text=ALL-UNNAMED \
      --add-opens java.base/java.time=ALL-UNNAMED \
      --add-opens java.base/java.util=ALL-UNNAMED \
      --add-opens java.base/java.util.concurrent=ALL-UNNAMED \
      --add-opens java.base/java.util.concurrent.atomic=ALL-UNNAMED \
      --add-opens java.base/java.util.concurrent.locks=ALL-UNNAMED \
      --add-opens java.base/jdk.internal.vm=ALL-UNNAMED \
      --add-opens java.base/sun.net.dns=ALL-UNNAMED \
      --add-opens java.base/sun.nio.ch=ALL-UNNAMED \
      --add-opens java.base/sun.nio.fs=ALL-UNNAMED \
      --add-opens java.base/sun.security.ssl=ALL-UNNAMED \
      --add-opens java.base/sun.security.util=ALL-UNNAMED \
      --add-opens java.desktop/com.apple.eawt=ALL-UNNAMED \
      --add-opens java.desktop/com.apple.eawt.event=ALL-UNNAMED \
      --add-opens java.desktop/com.apple.laf=ALL-UNNAMED \
      --add-opens java.desktop/com.sun.java.swing=ALL-UNNAMED \
      --add-opens java.desktop/com.sun.java.swing.plaf.gtk=ALL-UNNAMED \
      --add-opens java.desktop/java.awt=ALL-UNNAMED \
      --add-opens java.desktop/java.awt.dnd.peer=ALL-UNNAMED \
      --add-opens java.desktop/java.awt.event=ALL-UNNAMED \
      --add-opens java.desktop/java.awt.font=ALL-UNNAMED \
      --add-opens java.desktop/java.awt.image=ALL-UNNAMED \
      --add-opens java.desktop/java.awt.peer=ALL-UNNAMED \
      --add-opens java.desktop/javax.swing=ALL-UNNAMED \
      --add-opens java.desktop/javax.swing.plaf.basic=ALL-UNNAMED \
      --add-opens java.desktop/javax.swing.text=ALL-UNNAMED \
      --add-opens java.desktop/javax.swing.text.html=ALL-UNNAMED \
      --add-opens java.desktop/sun.awt=ALL-UNNAMED \
      --add-opens java.desktop/sun.awt.X11=ALL-UNNAMED \
      --add-opens java.desktop/sun.awt.datatransfer=ALL-UNNAMED \
      --add-opens java.desktop/sun.awt.image=ALL-UNNAMED \
      --add-opens java.desktop/sun.awt.windows=ALL-UNNAMED \
      --add-opens java.desktop/sun.font=ALL-UNNAMED \
      --add-opens java.desktop/sun.java2d=ALL-UNNAMED \
      --add-opens java.desktop/sun.lwawt=ALL-UNNAMED \
      --add-opens java.desktop/sun.lwawt.macosx=ALL-UNNAMED \
      --add-opens java.desktop/sun.swing=ALL-UNNAMED \
      --add-opens java.management/sun.management=ALL-UNNAMED \
      --add-opens jdk.attach/sun.tools.attach=ALL-UNNAMED \
      --add-opens jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED \
      --add-opens jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED \
      --add-opens jdk.jdi/com.sun.tools.jdi=ALL-UNNAMED \
      --enable-native-access=ALL-UNNAMED \
      -Djdk.lang.Process.launchMechanism=FORK \
      -Djava.awt.headless=true \
      -cp "$DIR/lib/*" com.jetbrains.ls.kotlinLsp.KotlinLspServerKt "$@"
    EOF
        substituteInPlace $out/bin/kotlin-lsp --replace-fail '@out@' "$out"
        chmod +x $out/bin/kotlin-lsp

        runHook postInstall
  '';

  # Don't strip the bundled JRE
  dontStrip = true;

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/kotlin-lsp"
    test -f "$out/libexec/kotlin-lsp/kotlin-lsp.sh"
  '';

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
