{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "gh-enhance";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "dlvhdr";
    repo = "gh-enhance";
    rev = "v${version}";
    hash = "sha256-g6nhEcBt72sol/49FVlYSo9HKtWHfj+zKw7FZ0ZjKXI=";
  };

  vendorHash = "sha256-us25CXQC3cd3BTa+wOYArbBiMtwkgpfeCQoD3S7+3rU=";

  meta = {
    description = "A terminal UI for GitHub Actions, companion to gh-dash";
    homepage = "https://github.com/dlvhdr/gh-enhance";
    license = lib.licenses.mit;
    mainProgram = "gh-enhance";
  };
}
