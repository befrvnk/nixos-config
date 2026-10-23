"""Compile native anchor selection with fake pointer state; no bus, display or menus."""

from pathlib import Path
import sys


original, patched = map(Path, sys.argv[1:])
header = (patched / "src/dbus/tray/tray_service.h").read_text()
start = header.index("struct TrayMenuAnchor {")
end = header.index("struct TrayItemInfo", start)
print(header[start:end])
print('''
struct PointerFixture {
  bool valid;
  double x, y;
  bool hasPointerPosition() const { return valid; }
  double lastPointerX() const { return x; }
  double lastPointerY() const { return y; }
};
''')
for namespace, root in (("before", original), ("after", patched)):
    text = (root / "src/shell/tray/tray_menu.cpp").read_text()
    if text.count("  int anchorX = 0;") != 1:
        raise ValueError("Native menu anchor selection changed")
    start = text.index("  int anchorX = 0;")
    end = text.index("\n  auto inst =", start)
    print(f"namespace {namespace} {{")
    print("TrayMenuAnchor select(std::optional<TrayMenuAnchor> m_anchor, PointerFixture* m_wayland) {")
    print(text[start:end])
    print("return {.x = static_cast<float>(anchorX), .y = static_cast<float>(anchorY)}; }")
    print("}")

# Guard the event-coordinate path through the actual callback wiring. Compilation
# of the full package additionally checks every real public C++ call-site type.
expected = {
    "src/shell/bar/widgets/tray_widget.cpp": "TrayMenuAnchor{.x = data.sceneX, .y = data.sceneY}",
    "src/dbus/tray/tray_service.cpp": "m_menuToggleCallback(itemId, contentScale, anchor);",
    "src/app/application_services.cpp": "m_trayMenu.toggleForItem(itemId, contentScale, anchor);",
    "src/shell/tray/tray_menu.cpp": "m_anchor = anchor;",
}
for name, snippet in expected.items():
    if (patched / name).read_text().count(snippet) != 1:
        raise ValueError(f"Captured menu anchor forwarding changed: {name}")
