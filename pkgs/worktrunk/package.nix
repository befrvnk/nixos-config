{
  lib,
  rustPlatform,
  pkg-config,
  libiconv,
  stdenv,
  tree-sitter,
  worktrunkSrc,
}:

rustPlatform.buildRustPackage {
  pname = "worktrunk";
  version = (builtins.fromTOML (builtins.readFile (worktrunkSrc + "/Cargo.toml"))).package.version;

  src = worktrunkSrc;
  cargoLock.lockFile = worktrunkSrc + "/Cargo.lock";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ tree-sitter ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  env.VERGEN_IDEMPOTENT = "1";
  doCheck = false;

  meta = {
    description = "Git worktree manager for parallel AI agent workflows";
    homepage = "https://worktrunk.dev/";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "wt";
    platforms = lib.platforms.unix;
  };
}
