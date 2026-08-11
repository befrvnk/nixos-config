{
  lib,
  fetchFromGitHub,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "kleinanzeigen-api";
  version = "0.4.0-send.1";
  pyproject = true;

  postPatch = ''
    ${python3Packages.python}/bin/python ${./add-send-command.py}
  '';

  src = fetchFromGitHub {
    owner = "monkrel";
    repo = "kleinanzeigen-api";
    rev = "efb2d82bf449c38a49558b8c71df8d888effbfd9";
    hash = "sha256-MHmdj8opExiJjaL+EO6Y+vHdvc7mOSasUPf/1KtzHoY=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = [ python3Packages."curl-cffi" ];

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/kleinanzeigen-api --categories > /dev/null
    $out/bin/kleinanzeigen-api send --help > /dev/null
  '';

  meta = {
    description = "Unofficial Python client and CLI for Kleinanzeigen.de";
    homepage = "https://github.com/monkrel/kleinanzeigen-api";
    license = lib.licenses.mit;
    mainProgram = "kleinanzeigen-api";
    platforms = lib.platforms.unix;
  };
}
