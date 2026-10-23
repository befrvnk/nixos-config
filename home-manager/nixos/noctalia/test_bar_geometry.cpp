// Device/display-free probe of the actual unmodified native before/after functions.
#include "render/animation/animation.h"
#include "render/core/color.h"
#include "shell/bar/bar_corner_shape.h"
#include "shell/surface/shadow.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include "native-bar-geometry.h"

static void require(bool ok, const char *message) {
  if (!ok) throw std::runtime_error(message);
}
static bool equal(float a, float b) { return std::abs(a - b) < 0.001F; }

int main() {
  int cases = 0;
  for (const std::string position : {"top", "bottom", "left", "right"})
    for (int mode = 0; mode < 3; ++mode)
      for (int gap : {0, 16, 24})
        for (bool hasShadow : {false, true})
          for (bool reserve : {false, true})
            for (auto direction : {ShadowDirection::Center, ShadowDirection::Up, ShadowDirection::DownRight}) {
              BarConfig cfg;
              cfg.position = position;
              cfg.thickness = 34;
              cfg.marginEdge = gap;
              cfg.marginEnds = 16;
              cfg.marginOppositeEdge = 7;
              cfg.shadow = hasShadow;
              cfg.reserveSpace = reserve;
              cfg.autoHide = mode == 1;
              cfg.smartAutoHide = mode == 2;
              cfg.concaveEdgeCorners = gap == 0;
              ShellConfig::ShadowConfig shadow;
              shadow.direction = direction;
              const auto oldSpec = before::computeBarSurfaceSpec(cfg, shadow);
              const auto spec = after::computeBarSurfaceSpec(cfg, shadow);
              const float oldW = oldSpec.surfaceWidth ? oldSpec.surfaceWidth : 1200;
              const float oldH = oldSpec.surfaceHeight ? oldSpec.surfaceHeight : 800;
              const float w = spec.surfaceWidth ? spec.surfaceWidth : 1200;
              const float h = spec.surfaceHeight ? spec.surfaceHeight : 800;
              const auto oldBody = before::computeBarVisualGeometry(cfg, shadow, oldW, oldH);
              const auto body = after::computeBarVisualGeometry(cfg, shadow, w, h);
              const float oldX = position == "right" ? 1200 - oldW - oldSpec.marginRight : oldSpec.marginLeft;
              const float oldY = position == "bottom" ? 800 - oldH - oldSpec.marginBottom : oldSpec.marginTop;
              const float x = position == "right" ? 1200 - w - spec.marginRight : spec.marginLeft;
              const float y = position == "bottom" ? 800 - h - spec.marginBottom : spec.marginTop;
              require(equal(oldX + oldBody.x, x + body.x), "Resting physical X changed");
              require(equal(oldY + oldBody.y, y + body.y), "Resting physical Y changed");
              require(equal(oldBody.width, body.width) && equal(oldBody.height, body.height), "Body size changed");
              require(before::reservedBarEdgeDistance(cfg, shadow) == after::reservedBarEdgeDistance(cfg, shadow),
                      "Compositor/panel reserved edge distance changed");
              require(spec.exclusiveZone == (reserve ? after::reservedBarExclusiveZone(cfg, shadow) : 0),
                      "Overlay incorrectly reserves space");
              require(after::barConfigUsesSlideSurface(cfg) == (mode != 0), "Pointer slide policy changed");
              require(after::barSupportsSlideBehavior(cfg) == before::barSupportsSlideBehavior(cfg),
                      "Auto-hide behavior changed");
              if (gap > 0) {
                const int anchored = position == "top" ? spec.marginTop : position == "bottom" ? spec.marginBottom
                                     : position == "left" ? spec.marginLeft : spec.marginRight;
                require(anchored == 0, "Surface must reach physical edge");
              }
              if (mode != 0 || gap == 0) {
                require(oldSpec.marginTop == spec.marginTop && oldSpec.marginRight == spec.marginRight
                        && oldSpec.marginBottom == spec.marginBottom && oldSpec.marginLeft == spec.marginLeft
                        && oldSpec.surfaceWidth == spec.surfaceWidth && oldSpec.surfaceHeight == spec.surfaceHeight
                        && oldSpec.exclusiveZone == spec.exclusiveZone, "Existing auto-hide/flush geometry changed");
              }
              const auto input = after::barContentInputRegion(cfg, shadow, static_cast<int>(w), static_cast<int>(h));
              require(equal(input.x, body.x) && equal(input.y, body.y)
                      && equal(input.width, body.width) && equal(input.height, body.height),
                      "Manual input region includes transparent gutter or loses body");
              ++cases;
            }

  BarConfig cfg;
  cfg.position = "top";
  cfg.marginEdge = 16;
  cfg.marginEnds = 16;
  cfg.radiusTopLeft = cfg.radiusTopRight = cfg.radiusBottomLeft = cfg.radiusBottomRight = 16;
  cfg.borderWidth = 1.0F;
  cfg.thickness = 34;
  cfg.shadow = false;
  cfg.reserveSpace = false;
  cfg.autoHide = false;
  cfg.smartAutoHide = false;
  ShellConfig::ShadowConfig shadow;
  const auto spec = after::computeBarSurfaceSpec(cfg, shadow);
  const auto body = after::computeBarVisualGeometry(cfg, shadow, 1200, spec.surfaceHeight);
  const auto delta = after::computeAutoHideHiddenDelta(false, false, false, 1200, spec.surfaceHeight,
                                                      body.x, body.y, body.x + body.width, body.y + body.height);
  require(spec.marginTop == 0 && spec.surfaceHeight == 50 && equal(body.y, 16), "Expected one 16px resting gap");
  require(body.y + body.height + delta.second < 0, "Hidden bar ink leaks onto display");
  const float quarterTop = body.y + delta.second * 0.75F;
  require(quarterTop < 0 && quarterTop + body.height > 0, "Slide must intersect physical edge before resting gap");
  require(after::barContentInputRegion(cfg, shadow, 1200, 50).y == 16, "Floating gap captures pointer input");
  require(before::ipcDuration(true) == 200 && before::ipcDuration(false) == 200, "Original timing changed");
  require(after::ipcDuration(true) == before::ipcDuration(true), "Entrance duration changed");
  require(after::ipcEasing(true) == before::ipcEasing(true), "Entrance easing changed");
  require(after::ipcDuration(false) == 100 && after::ipcEasing(false) == Easing::EaseOutCubic,
          "Expected fast 100ms ease-out exit");
  const float oldProgress60 = applyEasing(before::ipcEasing(false), 60.0F / before::ipcDuration(false));
  const float progress60 = applyEasing(after::ipcEasing(false), 60.0F / after::ipcDuration(false));
  require(body.y + body.height + delta.second * oldProgress60 > 0, "Slow-exit comparison is invalid");
  require(body.y + body.height + delta.second * progress60 < 0, "Fast exit still covers display after 60ms");
  require(equal(applyEasing(after::ipcEasing(false), 0.0F), 0.0F)
          && equal(applyEasing(after::ipcEasing(false), 1.0F), 1.0F), "Exit easing endpoints changed");
  std::cout << "Native before/after geometry: " << cases << " cases; edge-origin slide, one resting gap, no pointer reveal\n";
  std::cout << "Native IPC timing: entrance unchanged at 200ms; exit 100ms ease-out; bar ink offscreen by 60ms of its exit\n";
}
