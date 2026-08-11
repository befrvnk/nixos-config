{
  buildGoModule,
  lib,
}:

buildGoModule {
  pname = "kleinanzeigen-images";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  subPackages = [ "cmd/kleinanzeigen-images" ];

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/kleinanzeigen-images --help > /dev/null
  '';

  meta = {
    description = "Download public Kleinanzeigen listing images into a local manifest";
    license = lib.licenses.mit;
    mainProgram = "kleinanzeigen-images";
    platforms = lib.platforms.unix;
  };
}
