{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  stdenv,
  darwin,
}:

rustPlatform.buildRustPackage rec {
  pname = "worktrunk";
  version = "0.15.1";

  src = fetchFromGitHub {
    owner = "max-sixty";
    repo = "worktrunk";
    tag = "v${version}";
    hash = "sha256-/p3H3q2LgimLi9Ykqsr25d5A4kV1D0vM3ZpL3R/eXQQ=";
  };

  cargoHash = "sha256-60o9JLUSL3B7OpSMWdlsaAr7ZRaAKbAi8C88qMqKE/A=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    darwin.apple_sdk.frameworks.Security
    darwin.apple_sdk.frameworks.SystemConfiguration
  ];

  # The default feature includes tree-sitter for syntax highlighting
  buildFeatures = [ "default" ];

  # Tests require git repos and environment setup not available in sandbox
  doCheck = false;

  meta = {
    description = "A CLI for git worktree management, designed for running AI agents in parallel";
    homepage = "https://github.com/max-sixty/worktrunk";
    license = with lib.licenses; [
      mit
      asl20
    ];
    maintainers = [ ];
    mainProgram = "wt";
  };
}
