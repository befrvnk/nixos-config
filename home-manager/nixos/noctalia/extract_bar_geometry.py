"""Extract unmodified native geometry definitions for an offline before/after probe."""

from pathlib import Path
import re
import sys


def between(text, start, end):
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError(f"Native geometry boundaries changed: {start!r}, {end!r}")
    return text[text.index(start):text.index(end)]


def emit(root, namespace):
    bar = (root / "src/shell/bar/bar.cpp").read_text()
    reserved = (root / "src/shell/bar/bar_reserved_zone.h").read_text()
    reserved = "\n".join(line for line in reserved.splitlines() if not line.startswith("#"))
    gutter = "barSurfaceEdgeGutter" if "barSurfaceEdgeGutter" in bar else "barAutoHideEdgeGutter"
    print(f"namespace {namespace} {{")
    print(reserved)
    print(between(bar, "  [[nodiscard]] bool barConfigUsesSlideSurface", "  [[nodiscard]] bool barPointerHideAllowed"))
    print(between(bar, f"  [[nodiscard]] int {gutter}", "  [[nodiscard]] std::vector<InputRect>"))
    constant = re.search(r"constexpr float kAutoHideSlideExtraPx = [^;]+;", bar)
    if constant is None:
        raise ValueError("Native hidden-slide constant changed")
    print(constant.group())
    print(between(bar, "  struct BarVisualGeometry {", "  // Returns true when two bar configs"))
    print(between(bar, "  BarVisualGeometry computeBarVisualGeometry(", "  void applyBarShadowStyle("))
    ipc = between(bar, "void Bar::setInstanceIpcVisible(", "void Bar::applyIpcVisibility(")
    timing = re.findall(r"instance\.animations\.animate\(\s*current,\s*target,\s*([^,\n]+),\s*([^,\n]+),", ipc)
    if len(timing) != 1:
        raise ValueError("Native explicit-IPC animation arguments changed")
    duration, easing = timing[0]
    # Compile the native call-site expressions, not a second policy implementation.
    print(f"constexpr int ipcDuration(bool visible) {{ return {duration}; }}")
    print(f"constexpr Easing ipcEasing(bool visible) {{ return {easing}; }}")
    print("}")


original, patched = map(Path, sys.argv[1:])
# Use the actual native input-region value type, without its GUI surface class.
surface = (original / "src/wayland/surface.h").read_text()
print(between(surface, "struct InputRect {", "struct SurfaceIdleProfileEntry"))
palette = (original / "src/ui/palette.cpp").read_text()
print(between(palette, "ColorSpec colorSpecFromRole(", "ColorSpec fixedColorSpec("))
emit(original, "before")
emit(patched, "after")
