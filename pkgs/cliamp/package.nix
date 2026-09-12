{
  alsa-lib,
  buildGoModule,
  ffmpeg,
  flac,
  lib,
  libogg,
  libvorbis,
  makeWrapper,
  mpg123,
  pkg-config,
  src,
  stdenv,
  version,
  yt-dlp,
}:

buildGoModule {
  pname = "cliamp";
  inherit src version;

  vendorHash = "sha256-d/ENFm9b1DkIir1lz50VVX1pvuQpwPUVlA5XOC7Jj5o=";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    flac
    libogg
    libvorbis
    mpg123
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ alsa-lib ];

  postPatch = ''
    substituteInPlace go.mod --replace-fail 'go 1.26.6' 'go 1.26.5'
  '';

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${version}"
  ];

  postInstall = ''
    wrapProgram "$out/bin/cliamp" \
      --prefix PATH : ${
        lib.makeBinPath [
          ffmpeg
          yt-dlp
        ]
      }
  '';

  # macOS limits Unix socket paths to 104 bytes; use a shorter test directory.
  preCheck = lib.optionalString stdenv.hostPlatform.isDarwin ''
    export TMPDIR="$(mktemp -d /tmp/cliamp-XXXXXX)"
  '';

  __darwinAllowLocalNetworking = true;

  meta = {
    description = "Retro terminal music player inspired by Winamp";
    homepage = "https://github.com/bjarneo/cliamp";
    license = lib.licenses.mit;
    mainProgram = "cliamp";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
