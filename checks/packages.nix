{ lib, pkgs, ... }:
{
  home-cleanup = pkgs.callPackage ../pkgs/home-cleanup/package.nix { };

  pi-extension-tests = pkgs.runCommand "pi-extension-tests" { } ''
    test_files="$(${pkgs.findutils}/bin/find ${../home-manager/shared/pi/extensions} \( -name '*.test.ts' -o -name '*.test.mjs' \) | ${pkgs.coreutils}/bin/sort | ${pkgs.gnused}/bin/sed ':a;N;$!ba;s/\n/ /g')"
    ${pkgs.tsx}/bin/tsx --test --test-concurrency=1 $test_files
    touch $out
  '';

  pi-package-smoke = pkgs.runCommand "pi-package-smoke" { } ''
    PI_BIN=${pkgs.pi-coding-agent}/bin/pi \
      ${pkgs.bash}/bin/bash ${../scripts/smoke-test-pi-package.sh} ${../home-manager/shared/pi}
    touch $out
  '';

  inherit (pkgs)
    cliamp
    gh-enhance
    kleinanzeigen
    kotlin-lsp
    pi-coding-agent
    user-scanner
    ;
}
// lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  inherit (pkgs)
    domain-check
    idea-community
    ;
}
