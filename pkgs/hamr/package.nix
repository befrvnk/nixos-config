{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  quickshell,
  qt6Packages,
  python3,
  fd,
  fzf,
  wl-clipboard,
  cliphist,
  libqalculate,
  libnotify,
  jq,
  pulseaudio,
  xdg-utils,
  gtk3,
  gnome-desktop,
  playerctl,
  grim,
  slurp,
  tesseract,
}:

let
  python = python3.withPackages (ps: [
    ps.click
    ps.loguru
    ps.tqdm
    ps.pygobject3
  ]);

  # Wrap quickshell with Qt5Compat for GraphicalEffects module
  quickshellWrapped = quickshell.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/quickshell \
        --prefix QML2_IMPORT_PATH : "${qt6Packages.qt5compat}/lib/qt-6/qml"
    '';
  });
in
stdenvNoCC.mkDerivation rec {
  pname = "hamr";
  version = "0.17.4";

  src = fetchFromGitHub {
    owner = "Stewart86";
    repo = "hamr";
    rev = "v${version}";
    hash = "sha256-KVUcoSRB9nNXQ0x8JHyuuvHVXWC1qnqMzgD5qM7A00U=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Patch apps plugin to use XDG_DATA_DIRS (like Vicinae does)
  postPatch = ''
    substituteInPlace plugins/apps/handler.py \
      --replace-fail \
        'APP_DIRS = [' \
        'APP_DIRS = [Path(d) / "applications" for d in os.environ.get("XDG_DATA_DIRS", "").split(":") if d] + ['
  '';

  buildInputs = [
    quickshellWrapped
    python
  ];

  # Runtime dependencies
  runtimeDeps = [
    quickshellWrapped
    python
    fd
    fzf
    wl-clipboard
    cliphist
    libqalculate
    libnotify
    jq
    pulseaudio
    xdg-utils
    gtk3
    gnome-desktop
    playerctl
    grim
    slurp
    tesseract
  ];

  installPhase = ''
    runHook preInstall

    # Install quickshell configuration
    mkdir -p $out/share/quickshell/hamr
    cp -r . $out/share/quickshell/hamr/

    # Install the launcher script
    mkdir -p $out/bin
    cp hamr $out/bin/hamr
    chmod +x $out/bin/hamr

    # Wrap the launcher with runtime dependencies
    wrapProgram $out/bin/hamr \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}

    # Install systemd user service
    mkdir -p $out/lib/systemd/user
    cat > $out/lib/systemd/user/hamr.service <<EOF
    [Unit]
    Description=Hamr Launcher Daemon
    PartOf=graphical-session.target
    After=graphical-session.target

    [Service]
    Type=simple
    ExecStart=$out/bin/hamr
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=graphical-session.target
    EOF

    runHook postInstall
  '';

  meta = {
    description = "Extensible launcher for Wayland compositors built with Quickshell";
    homepage = "https://github.com/Stewart86/hamr";
    license = lib.licenses.gpl3Plus;
    maintainers = [ ];
    platforms = lib.platforms.linux;
    mainProgram = "hamr";
  };
}
