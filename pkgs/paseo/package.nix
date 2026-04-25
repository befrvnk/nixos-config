{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  copyDesktopItems,
  coreutils,
  dpkg,
  makeDesktopItem,
  makeWrapper,
  wrapGAppsHook3,
  xdg-utils,
  alsa-lib,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libnotify,
  libsecret,
  libuuid,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxscrnsaver,
  libxtst,
  libxcb,
  mesa,
  nspr,
  nss,
  pango,
  udev,
  vips_8_17,
}:

stdenv.mkDerivation rec {
  pname = "paseo";
  version = "0.1.62";

  src = fetchurl {
    url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-${version}-amd64.deb";
    hash = "sha256-WWYxueyL6qewH0iwxwzSZ4gV1lSZ63s2O7EM4i95KAk=";
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    dpkg
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    atk
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libnotify
    libsecret
    libuuid
    libxkbcommon
    mesa
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    udev
    (lib.getLib vips_8_17)
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxscrnsaver
    libxtst
    libxcb
  ];

  dontWrapGApps = true;
  autoPatchelfIgnoreMissingDeps = [ "libvips-cpp.so.8.17.3" ];

  installPhase = ''
    runHook preInstall

    mkdir -p pkgroot "$out/bin" "$out/lib" "$out/share"
    dpkg-deb -x "$src" pkgroot

    cp -r pkgroot/opt/Paseo "$out/lib/paseo"
    chmod -R u+w "$out/lib/paseo"
    patchShebangs "$out/lib/paseo"

    mkdir -p "$out/share/icons"
    cp -r pkgroot/usr/share/icons/hicolor "$out/share/icons/"

    # The app bundle is immutable in the Nix store, so disable in-app updates.
    rm -f "$out/lib/paseo/resources/app-update.yml"

    # Keep only Linux x86_64 native modules to avoid patching irrelevant binaries.
    rm -rf "$out/lib/paseo/resources/app.asar.unpacked/node_modules/@mariozechner/clipboard-linux-x64-musl"
    for dir in "$out/lib/paseo/resources/app.asar.unpacked/node_modules/koffi/build/koffi"/*; do
      if [ "$(basename "$dir")" != "linux_x64" ]; then
        rm -rf "$dir"
      fi
    done

    # sharp expects the vendored libvips filename from upstream's optional package.
    ln -s ${lib.getLib vips_8_17}/lib/libvips-cpp.so.42.19.3 \
      "$out/lib/paseo/resources/app.asar.unpacked/node_modules/@img/sharp-linux-x64/lib/libvips-cpp.so.8.17.3"

    makeWrapper "$out/lib/paseo/Paseo.bin" "$out/bin/paseo-desktop" \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}" \
      --prefix PATH : "${
        lib.makeBinPath [
          coreutils
          xdg-utils
        ]
      }" \
      --add-flags "--no-sandbox" \
      --add-flags "--ozone-platform-hint=auto" \
      --add-flags "--enable-features=WaylandWindowDecorations" \
      --add-flags "--enable-wayland-ime=true"

    makeWrapper "$out/lib/paseo/Paseo.bin" "$out/bin/paseo" \
      --set ELECTRON_RUN_AS_NODE 1 \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}" \
      --prefix PATH : "${
        lib.makeBinPath [
          coreutils
          xdg-utils
        ]
      }" \
      --add-flags "--disable-warning=DEP0040" \
      --add-flags "$out/lib/paseo/resources/app.asar.unpacked/dist/daemon/node-entrypoint-runner.js" \
      --add-flags "node-script" \
      --add-flags "$out/lib/paseo/resources/app.asar/node_modules/@getpaseo/cli/dist/index.js"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "paseo";
      exec = "paseo-desktop %U";
      icon = "Paseo";
      desktopName = "Paseo";
      genericName = "AI agent desktop app";
      comment = "One interface for Claude Code, Codex, and OpenCode agents";
      categories = [
        "Development"
        "Utility"
      ];
      startupNotify = true;
      startupWMClass = "Paseo";
    })
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/paseo"
    test -x "$out/bin/paseo-desktop"
    test -x "$out/lib/paseo/Paseo.bin"
    test -f "$out/lib/paseo/resources/app.asar"
    test -f "$out/share/applications/paseo.desktop"
    test -f "$out/share/icons/hicolor/128x128/apps/Paseo.png"
  '';

  meta = {
    description = "Desktop and CLI interface for Claude Code, Codex, and OpenCode agents";
    homepage = "https://github.com/getpaseo/paseo";
    changelog = "https://github.com/getpaseo/paseo/releases/tag/v${version}";
    license = lib.licenses.agpl3Plus;
    mainProgram = "paseo-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
