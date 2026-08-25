{ cliampSrc }:

final: _prev: {
  cliamp = final.callPackage ../pkgs/cliamp/package.nix {
    src = cliampSrc;
    version = "main-${cliampSrc.shortRev or "dirty"}";
  };
}
