final: prev: {
  orca-ai = final.callPackage (
    if final.stdenv.hostPlatform.isDarwin then
      ../pkgs/orca-ai/darwin.nix
    else
      ../pkgs/orca-ai/package.nix
  ) { };
}
