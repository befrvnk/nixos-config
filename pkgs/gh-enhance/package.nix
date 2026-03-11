{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "gh-enhance";
  version = "0.5.1";

  src = fetchFromGitHub {
    owner = "dlvhdr";
    repo = "gh-enhance";
    rev = "v${version}";
    hash = "sha256-IHtI8wnPLMkqxdBFXqkt6inYMOIqKjdTKdZbTxIhPzo=";
  };

  vendorHash = "sha256-rgql0vsHAzWeubw4EYBu/yPmm2QeADsIeACWsbcWtSk=";

  meta = {
    description = "A terminal UI for GitHub Actions, companion to gh-dash";
    homepage = "https://github.com/dlvhdr/gh-enhance";
    license = lib.licenses.mit;
    mainProgram = "gh-enhance";
  };
}
