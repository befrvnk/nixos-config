{
  buildGoModule,
  lib,
}:

buildGoModule {
  pname = "kleinanzeigen";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  subPackages = [ "cmd/kleinanzeigen" ];

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/kleinanzeigen version | grep -Fx 0.1.0
    $out/bin/kleinanzeigen images --help > /dev/null
  '';

  meta = {
    description = "Kleinanzeigen command-line client";
    license = lib.licenses.mit;
    mainProgram = "kleinanzeigen";
    platforms = lib.platforms.unix;
  };
}
