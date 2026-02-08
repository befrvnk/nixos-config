{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  makeWrapper,
  whois,
}:

rustPlatform.buildRustPackage {
  pname = "domain-check";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "saidutt46";
    repo = "domain-check";
    rev = "v0.6.0";
    hash = "sha256-QH3gkFPKNnULG+QTmaPg1Gb9KD99ao7BCkFeJQcZFu8=";
  };

  cargoHash = "sha256-60BDLAwpSKvdiFs+Gg7h3kEVbD4MwMVmIJOIS0Yvoio=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];
  buildInputs = [ openssl ];

  # Integration tests require network access (RDAP/WHOIS queries)
  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/domain-check \
      --prefix PATH : ${lib.makeBinPath [ whois ]}
  '';

  meta = {
    description = "Fast CLI tool for checking domain availability using RDAP with WHOIS fallback";
    homepage = "https://github.com/saidutt46/domain-check";
    license = lib.licenses.mit;
    mainProgram = "domain-check";
  };
}
