{
  lib,
  python3Packages,
  fetchPypi,
}:
python3Packages.buildPythonApplication rec {
  pname = "user-scanner";
  version = "1.0.8.1";
  pyproject = true;

  src = fetchPypi {
    pname = "user_scanner";
    inherit version;
    hash = "sha256-d4+oLf3k+EmxUWCH2S5NSLpnOeF4gRQmvDVqlNxZuLY=";
  };

  build-system = [ python3Packages.flit-core ];

  dependencies = with python3Packages; [
    colorama
    httpx
  ];

  doCheck = false;
  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/user-scanner --help > /dev/null
  '';

  meta = {
    description = "Multi-platform username availability checker";
    homepage = "https://github.com/kaifcodec/user-scanner";
    license = lib.licenses.mit;
    mainProgram = "user-scanner";
  };
}
