"""Extract unmodified native geometry definitions for an offline before/after probe.

Definitions are taken by matching braces from their signature, so the probe copies whole
functions instead of text between markers that move with upstream refactors.
"""

from pathlib import Path
import re
import sys


def body_end(text, start):
    depth = 0
    i = text.index("{", start)
    in_line_comment = False
    in_string = None
    while i < len(text):
        c = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
        elif in_string:
            if c == "\\":
                i += 1
            elif c == in_string:
                in_string = None
        elif c == "/" and nxt == "/":
            in_line_comment = True
            i += 1
        elif c in "\"'":
            in_string = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                if text[end:end + 1] == ";":
                    end += 1
                return end
        i += 1
    raise ValueError("unbalanced braces")


def definition_start(text, index):
    start = text.rfind("\n", 0, index) + 1
    while start > 0:
        previous_end = start - 1
        previous_start = text.rfind("\n", 0, previous_end) + 1
        previous = text[previous_start:previous_end]
        stripped = previous.rstrip()
        is_type_line = (
            previous.startswith("  ")
            and stripped
            and not stripped.endswith((";", "{", "}", ")"))
            and not stripped.lstrip().startswith("//")
        )
        if not is_type_line:
            break
        start = previous_start
    return start


def definition(text, pattern):
    matches = list(re.finditer(pattern, text))
    if len(matches) != 1:
        raise ValueError(f"Native geometry definition changed ({len(matches)} matches): {pattern!r}")
    match = matches[0]
    line = match.start() + (1 if text[match.start()] == "\n" else 0)
    return text[definition_start(text, line):body_end(text, line)]


def emit(root, namespace):
    bar = (root / "src/shell/bar/bar.cpp").read_text()
    reserved = (root / "src/shell/bar/bar_reserved_zone.h").read_text()
    reserved = "\n".join(line for line in reserved.splitlines() if not line.startswith("#"))
    print(f"namespace {namespace} {{")
    print(reserved)

    constant = re.search(r"constexpr float kAutoHideSlideExtraPx = [^;]+;", bar)
    if constant is None:
        raise ValueError("Native hidden-slide constant changed")
    print(constant.group())

    slide = re.search(r"  bool (\w+)\(const BarConfig& cfg\) noexcept \{ return cfg\.isAutoHideEnabled\(\); \}", bar)
    if slide is None:
        raise ValueError("Native slide predicate changed")
    print(f"bool barConfigUsesSlideSurface(const BarConfig& cfg) noexcept {{ return cfg.isAutoHideEnabled(); }}")
    print(f"bool barSupportsSlideBehavior(const BarConfig& cfg) noexcept {{ return cfg.isAutoHideEnabled(); }}")

    print(definition(bar, r"\n  int (barAutoHideEdgeGutter|barSurfaceEdgeGutter)\(const BarConfig& cfg\)"))
    print(definition(bar, r"\n  struct BarVisualGeometry \{"))
    print(definition(bar, r"\n  struct BarSurfaceSpec \{"))
    print(definition(bar, r"\n  BarSurfaceSpec computeBarSurfaceSpec\("))
    print(definition(bar, r"\n  barInnerSurfaceExtension\(const BarConfig& cfg"))
    print(definition(bar, r"\n  BarVisualGeometry computeBarVisualGeometry\("))
    print(definition(bar, r"\n  InputRect barContentInputRegion\("))
    print(definition(bar, r"\n  std::pair<float, float> computeAutoHideHiddenDelta\("))

    ipc_start = bar.index("void Bar::setInstanceIpcVisible(")
    ipc = bar[ipc_start:body_end(bar, ipc_start)]
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
surface = (original / "lib/wayland/surface.h").read_text()
print(surface[surface.index("struct InputRect {"):surface.index("struct SurfaceIdleProfileEntry")])
palette = (original / "lib/ui/palette.cpp").read_text()
print(palette[palette.index("ColorSpec colorSpecFromRole("):palette.index("ColorSpec fixedColorSpec(")])
emit(original, "before")
emit(patched, "after")
