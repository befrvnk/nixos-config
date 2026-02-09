# IntelliJ IDEA (Unified Edition) - fetched from JetBrains CDN
# Starting with 2025.3, JetBrains unified Community and Ultimate into a single product.
# Community features remain free. EAP builds are available from the JetBrains CDN.
# See: https://blog.jetbrains.com/idea/2025/12/intellij-idea-unified-release/
{
  lib,
  stdenv,
  fetchzip,
  makeWrapper,
  autoPatchelfHook,
  wrapGAppsHook3,
  # JDK - use the JetBrains JDK for best compatibility
  jetbrains,
  # Runtime dependencies
  coreutils,
  gnugrep,
  which,
  git,
  python3,
  # Library dependencies for autoPatchelf
  alsa-lib,
  cups,
  fontconfig,
  freetype,
  glib,
  gtk3,
  libdrm,
  libGL,
  libnotify,
  libsecret,
  libX11,
  libxcb,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libxkbcommon,
  libXrandr,
  libXrender,
  libXtst,
  mesa,
  nspr,
  nss,
  pango,
  udev,
  libxshmfence,
  linux-pam,
  audit,
  zlib,
  # For desktop file
  copyDesktopItems,
  makeDesktopItem,
}:

let
  buildNumber = "261.20362.25";
in
stdenv.mkDerivation rec {
  pname = "idea-community";
  version = "2026.1-eap3";

  src = fetchzip {
    url = "https://download.jetbrains.com/idea/idea-${buildNumber}.tar.gz";
    hash = "sha256-ds9/pUL2OfKTZ8rXmoOhDPgW/IeCiOpSsMAI2lROFOc=";
  };

  nativeBuildInputs = [
    makeWrapper
    autoPatchelfHook
    wrapGAppsHook3
    copyDesktopItems
  ];

  # Libraries needed by the IDE binaries
  buildInputs = [
    alsa-lib
    cups
    fontconfig
    freetype
    glib
    gtk3
    libdrm
    libGL
    libnotify
    libsecret
    libX11
    libxcb
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libxkbcommon
    libXrandr
    libXrender
    libXtst
    mesa
    nspr
    nss
    pango
    udev
    libxshmfence
    linux-pam
    audit
    zlib
    stdenv.cc.cc.lib
  ];

  # Don't wrap twice
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    # Install IDE files
    mkdir -p $out/share/idea-community
    cp -r . $out/share/idea-community/

    # Use the bundled JBR (JetBrains Runtime) if available, otherwise use system JDK
    if [ -d "$out/share/idea-community/jbr" ]; then
      echo "Using bundled JetBrains Runtime"
      jdk="$out/share/idea-community/jbr"
    else
      echo "Bundled JBR not found, linking system JetBrains JDK"
      ln -s ${jetbrains.jdk} $out/share/idea-community/jbr
      jdk="${jetbrains.jdk}"
    fi

    # Create wrapper script
    mkdir -p $out/bin
    makeWrapper $out/share/idea-community/bin/idea "$out/bin/idea-community" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : "${
        lib.makeBinPath [
          coreutils
          gnugrep
          which
          git
          python3
        ]
      }" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}" \
      --set IDEA_JDK "$jdk" \
      --set JAVA_HOME "$jdk" \
      --set JDK_HOME "$jdk" \
      --set IDEA_VM_OPTIONS "$out/share/idea-community/bin/idea64.vmoptions" \
      --add-flags "-Dawt.toolkit.name=WLToolkit"

    # Install icons
    for size in 16 32 48 64 128 256 512; do
      icon="$out/share/idea-community/bin/idea.png"
      if [ -f "$icon" ]; then
        mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
        cp "$icon" $out/share/icons/hicolor/''${size}x''${size}/apps/idea-community.png
      fi
    done

    # Also install SVG icon if available
    if [ -f "$out/share/idea-community/bin/idea.svg" ]; then
      mkdir -p $out/share/icons/hicolor/scalable/apps
      cp "$out/share/idea-community/bin/idea.svg" $out/share/icons/hicolor/scalable/apps/idea-community.svg
    fi

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "idea-community";
      exec = "idea-community %U";
      icon = "idea-community";
      desktopName = "IntelliJ IDEA";
      genericName = "Integrated Development Environment";
      comment = "Java, Kotlin, Groovy, and Scala IDE";
      categories = [
        "Development"
        "IDE"
        "Java"
      ];
      mimeTypes = [
        "text/x-java-source"
        "text/x-kotlin"
        "text/x-scala"
        "application/xml"
        "text/plain"
      ];
      startupNotify = true;
      startupWMClass = "jetbrains-idea";
    })
  ];

  # For compatibility with jetbrains.plugins.addPlugins
  passthru = {
    inherit buildNumber;
  };

  meta = {
    description = "Java, Kotlin, Groovy and Scala IDE from JetBrains";
    longDescription = ''
      IntelliJ IDEA is a unified IDE for Java, Kotlin, Groovy, and Scala
      development. It provides smart code completion, powerful refactoring
      tools, and integrated version control. Community features are free
      for both non-commercial and commercial use.
    '';
    homepage = "https://www.jetbrains.com/idea/";
    changelog = "https://youtrack.jetbrains.com/articles/IDEA-A-2100662619/IntelliJ-IDEA-2026.1-EAP-3-261.20362.25-build-Release-Notes";
    license = lib.licenses.asl20;
    maintainers = [ ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "idea-community";
  };
}
