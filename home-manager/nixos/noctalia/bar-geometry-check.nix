{
  patches,
  pkgs,
  source,
}:
let
  patched = pkgs.applyPatches {
    name = "noctalia-bar-geometry-source";
    src = source;
    inherit patches;
    patchFlags = [
      "-p1"
      "--fuzz=0"
    ];
  };
in
pkgs.runCommandCC "noctalia-bar-geometry-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    mkdir -p $out/bin
    python3 ${./extract_bar_geometry.py} ${source} ${patched} > native-bar-geometry.h
    $CXX -std=c++23 -ffunction-sections -fdata-sections -Wl,--gc-sections \
      -I. -I${patched}/src ${./test_bar_geometry.cpp} \
      ${patched}/src/shell/surface/shadow.cpp \
      ${patched}/src/render/animation/animation.cpp -o $out/bin/probe
    $out/bin/probe
  ''
