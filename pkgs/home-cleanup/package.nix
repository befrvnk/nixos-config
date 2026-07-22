{
  buildGoModule,
  coreutils,
  git,
  lib,
  makeWrapper,
}:

buildGoModule {
  pname = "home-cleanup";
  version = "0.2.1";

  src = ./.;
  vendorHash = null;

  subPackages = [ "cmd/home-cleanup" ];

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    coreutils
    git
  ];

  postInstall = ''
    wrapProgram $out/bin/home-cleanup \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          git
        ]
      }
  '';

  meta = {
    description = "Dry-run-first cleanup for reproducible developer caches";
    license = lib.licenses.mit;
    mainProgram = "home-cleanup";
    platforms = lib.platforms.unix;
  };
}
