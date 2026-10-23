{
  patches,
  pkgs,
  source,
}:
let
  patched = pkgs.applyPatches {
    name = "noctalia-tray-anchor-source";
    src = source;
    inherit patches;
    patchFlags = [
      "-p1"
      "--fuzz=0"
    ];
  };
in
pkgs.runCommandCC "noctalia-tray-anchor-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    mkdir -p $out/bin
    python3 ${./extract_tray_anchor.py} ${source} ${patched} > native-tray-anchor.h
    $CXX -std=c++23 -I. ${./test_tray_anchor.cpp} -o $out/bin/probe
    $out/bin/probe
  ''
