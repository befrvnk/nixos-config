{
  patches,
  pkgs,
  source,
}:
let
  patched = pkgs.applyPatches {
    name = "noctalia-battery-warning-source";
    src = source;
    inherit patches;
    patchFlags = [
      "-p1"
      "--fuzz=0"
    ];
  };
in
pkgs.runCommandCC "noctalia-battery-warning-check" { } ''
  # applyPatches above proves every local Noctalia patch still applies with fuzz=0. Then compile
  # the patched battery warning monitor against Noctalia's real headers (the sdbus-backed UPower
  # header is mirrored in battery-warning-stubs/) and drive it through the discharge/charge flap
  # sequences that used to repeat low-battery toasts while the charger was connected.
  $CXX -std=c++23 -O2 \
    -I${./battery-warning-stubs} \
    -I${patched}/src \
    ${./test_battery_warning.cpp} \
    ${patched}/src/system/battery_warning_monitor.cpp \
    -o battery-warning-probe
  ./battery-warning-probe
  touch $out
''
