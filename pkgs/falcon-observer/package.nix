{
  buildGoModule,
  lib,
}:

buildGoModule rec {
  pname = "falcon-observer";
  version = "0.1.1";

  src = ./.;
  vendorHash = null;

  subPackages = [ "cmd/falcon-observer" ];

  env.CGO_ENABLED = "1";
  ldflags = [
    "-X github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/app.Version=${version}"
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/falcon-observer version | grep -Fx ${version}
  '';

  meta = {
    description = "Automatic Gradle-triggered CrowdStrike Falcon performance observer for macOS";
    license = lib.licenses.mit;
    mainProgram = "falcon-observer";
    platforms = lib.platforms.darwin;
  };
}
