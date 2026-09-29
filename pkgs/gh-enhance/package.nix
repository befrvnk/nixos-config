{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_27,
}:

(buildGoModule.override { go = go_1_27; }) rec {
  pname = "gh-enhance";
  version = "0.7.2";

  src = fetchFromGitHub {
    owner = "dlvhdr";
    repo = "gh-enhance";
    rev = "v${version}";
    hash = "sha256-n75RASNnuGNSwzCZlag4qHFnNswTVbjRmbM3yrB6GVg=";
  };

  vendorHash = "sha256-ZMocJFBRMB7gddQaSeR/Sa1A0OL5WDsxmOl8w5yUZh0=";

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/gh-enhance --help > /dev/null
  '';

  meta = {
    description = "A terminal UI for GitHub Actions, companion to gh-dash";
    homepage = "https://github.com/dlvhdr/gh-enhance";
    license = lib.licenses.mit;
    mainProgram = "gh-enhance";
  };
}
