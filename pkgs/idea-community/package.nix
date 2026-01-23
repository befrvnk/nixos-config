# IntelliJ IDEA Community Edition - fetched from GitHub releases
# JetBrains discontinued IDEA Community binaries on their CDN in July 2025,
# but continues publishing pre-built binaries to GitHub releases.
# See: https://blog.jetbrains.com/idea/2025/07/intellij-idea-unified-distribution-plan/
#
# Update with: ./scripts/update-idea-community.sh
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
  xorg,
  zlib,
  # For desktop file
  copyDesktopItems,
  makeDesktopItem,
}:

stdenv.mkDerivation rec {
  pname = "idea-community";
  version = "2025.3.2";

  src = fetchzip {
    url = "https://github.com/JetBrains/intellij-community/releases/download/idea/${version}/idea-${version}.tar.gz";
    hash = "sha256-hllhjl0AZcNzT3pvb1iNVNoQR/rUT2u/ryKdTxfGVYA=";
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
    xorg.libxshmfence
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
      --set IDEA_VM_OPTIONS "$out/share/idea-community/bin/idea64.vmoptions"

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
      desktopName = "IntelliJ IDEA Community Edition";
      genericName = "Integrated Development Environment";
      comment = "Free Java, Kotlin, Groovy, and Scala IDE";
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
      startupWMClass = "jetbrains-idea-ce";
    })
  ];

  # For compatibility with jetbrains.plugins.addPlugins
  passthru = {
    # Used by nix-jetbrains-plugins for plugin lookup
    buildNumber = version;
  };

  meta = {
    description = "Free Java, Kotlin, Groovy and Scala IDE from JetBrains";
    longDescription = ''
      IntelliJ IDEA Community Edition is a free and open-source IDE for Java,
      Kotlin, Groovy, and Scala development. It provides smart code completion,
      powerful refactoring tools, and integrated version control.

      This package fetches pre-built binaries from JetBrains GitHub releases
      since the official JetBrains CDN no longer provides Community Edition builds.
    '';
    homepage = "https://www.jetbrains.com/idea/";
    changelog = "https://github.com/JetBrains/intellij-community/releases/tag/idea/${version}";
    license = lib.licenses.asl20;
    maintainers = [ ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "idea-community";
  };
}
