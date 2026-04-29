final: prev: {
  paseo = final.callPackage (
    if final.stdenv.hostPlatform.isDarwin then ../pkgs/paseo/darwin.nix else ../pkgs/paseo/package.nix
  ) { };
}
