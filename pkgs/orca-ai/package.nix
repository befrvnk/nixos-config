{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  copyDesktopItems,
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
}:

stdenv.mkDerivation rec {
  pname = "orca-ai";
  version = "1.3.6";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca_${version}_amd64.deb";
    hash = "sha256-w1+hy+A02/QW2TXF26r/4VtjW7nnYetTExtq0TmAbnk=";
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

  installPhase = ''
    runHook preInstall

    mkdir -p pkgroot "$out/bin" "$out/lib" "$out/share"
    dpkg-deb -x "$src" pkgroot

    cp -r pkgroot/opt/Orca "$out/lib/orca-ai"

    mkdir -p "$out/share/icons"
    cp -r pkgroot/usr/share/icons/hicolor "$out/share/icons/"

    for icon in "$out"/share/icons/hicolor/*/apps/orca.png; do
      mv "$icon" "''${icon%/orca.png}/orca-ai.png"
    done

    patchShebangs "$out/lib/orca-ai/resources/bin"
    chmod +x "$out/lib/orca-ai/resources/bin/orca"

    # The app bundle is immutable in the Nix store, so disable in-app updates.
    rm -f "$out/lib/orca-ai/resources/app-update.yml"

    makeWrapper "$out/lib/orca-ai/orca" "$out/bin/orca-ai" \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}" \
      --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --add-flags "--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true"

    makeWrapper "$out/lib/orca-ai/resources/bin/orca" "$out/bin/orca-ai-cli"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "orca-ai";
      exec = "orca-ai %U";
      icon = "orca-ai";
      desktopName = "Orca";
      genericName = "AI agent IDE";
      comment = "Next-gen IDE for building with coding agents";
      categories = [
        "Development"
        "Utility"
      ];
      startupNotify = true;
      startupWMClass = "Orca";
    })
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/orca-ai"
    test -x "$out/bin/orca-ai-cli"
    test -x "$out/lib/orca-ai/orca"
    test -f "$out/share/applications/orca-ai.desktop"
    test -f "$out/share/icons/hicolor/256x256/apps/orca-ai.png"
  '';

  meta = {
    description = "Next-gen IDE for building with coding agents";
    homepage = "https://github.com/stablyai/orca";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "orca-ai";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
