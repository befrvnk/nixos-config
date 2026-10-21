{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_27,
}:

(buildGoModule.override { go = go_1_27; }) rec {
  pname = "gh-enhance";
  version = "0.8.1";

  src = fetchFromGitHub {
    owner = "dlvhdr";
    repo = "gh-enhance";
    rev = "v${version}";
    hash = "sha256-W7EyYi/Ycyu9WcWxPexJJTGkcHWveY4xsySfEZKy5/c=";
  };

  vendorHash = "sha256-gPs05ByMdsfjjY4rVp8UYX9OkfJ1BkUl4ywiFIBen8w=";

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
