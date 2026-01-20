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
  version = "0.17.0";

  src = fetchFromGitHub {
    owner = "max-sixty";
    repo = "worktrunk";
    tag = "v${version}";
    hash = "sha256-VCTcKR/84hUmkxlwX/h0+FHn2dUw8MfQ98HUUaczm/Q=";
  };

  cargoLock.lockFile = src + "/Cargo.lock";

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
