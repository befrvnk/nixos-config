#include <cmath>
#include <iostream>
#include <optional>
#include <stdexcept>
#include "native-tray-anchor.h"

static void require(bool ok, const char* message) {
  if (!ok) throw std::runtime_error(message);
}
static bool at(TrayMenuAnchor p, float x, float y) { return p.x == x && p.y == y; }

int main() {
  // Reproduce click/release followed by leave in the same queued Wayland frame.
  PointerFixture left{false, 1012, 33};
  TrayMenuAnchor clicked{1012, 33};
  require(at(before::select(clicked, &left), 0, 0), "Original zero-anchor reproduction changed");
  require(at(after::select(clicked, &left), 1012, 33), "Click position lost after pointer leave");
  PointerFixture moved{true, 8, 9};
  require(at(after::select(clicked, &moved), 1012, 33), "Later pointer motion overrides clicked icon");
  require(at(after::select(TrayMenuAnchor{0, 0}, &moved), 0, 0), "Zero click coords treated as absent");
  require(at(after::select(TrayMenuAnchor{1012.75F, 33.25F}, &moved), 1013, 33),
          "Fractional surface-local click was scaled or offset instead of rounded");
  PointerFixture valid{true, 400.75, 32.25};
  require(at(after::select(std::nullopt, &valid), 400, 32), "Legacy valid-pointer fallback changed");
  require(at(after::select(std::nullopt, &left), 0, 0), "Legacy absent-pointer fallback changed");
  std::cout << "Native tray anchor: original (0,0) reproduced; captured surface-local click survives leave/motion; fallbacks preserved\n";
}
