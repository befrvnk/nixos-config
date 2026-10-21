"""Adapt maintained XML definitions; validate in real headless style managers."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

import prepare_theme_output as migration


class GtkSourceviewThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "state/stylix.xml"
        self.output.parent.mkdir()
        self.search = self.root / "styles"
        self.search.mkdir()
        (self.search / "stylix.xml").symlink_to(self.output)
        self.template = Path(os.environ["GTKSOURCE_TEMPLATE"])
        self.environment = dict(os.environ, HOME=str(self.root),
                                XDG_CONFIG_HOME=str(self.root / "config"),
                                XDG_DATA_HOME=str(self.root / "data"),
                                XDG_STATE_HOME=str(self.root / "state"))
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS",
                    "NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME"):
            self.environment.pop(key, None)

    def render(self, palette, mode):
        tokens = set(re.findall(r"colors\.([a-z_0-9]+)\.default\.hex", self.template.read_text()))
        fixture = self.root / "colors.json"
        fixture.write_text(json.dumps({
            name: {token: color for token in tokens} for name, color in palette.items()
        }))
        result = subprocess.run([
            os.environ["NOCTALIA_BIN"], "theme", "--theme-json", str(fixture), "--both",
            "--default-mode", mode, "--render", f"{self.template}:{self.output}",
        ], env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("{{", self.output.read_text())
        return ET.parse(self.output).getroot()

    def probe(self, major):
        result = subprocess.run([
            sys.executable, os.environ["GTKSOURCE_PROBE"], os.environ[f"GTKSOURCE{major}_LIB"], str(self.search),
        ], env=self.environment, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_preserved_syntax_style_definitions_and_legacy_scheme_id(self):
        original = Path(os.environ["GTKSOURCE_ORIGINAL_TEMPLATE"])
        before = ET.parse(original).getroot()
        after = ET.parse(self.template).getroot()
        self.assertEqual(before.attrib["id"], after.attrib["id"])
        self.assertEqual(after.attrib["id"], "stylix")
        self.assertEqual(after.attrib["_name"], "Noctalia")
        self.assertEqual([item.attrib for item in before.findall("style")],
                         [item.attrib for item in after.findall("style")])
        self.assertEqual([item.attrib["name"] for item in before.findall("color")],
                         [item.attrib["name"] for item in after.findall("color")])

    def test_two_palettes_and_modes_render_valid_xml_color_definitions(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                root = self.render(palette, mode)
                colors = root.findall("color")
                self.assertEqual(len(colors), 16)
                self.assertTrue(all(color.attrib["value"] == expected for color in colors))
                self.assertGreater(len(root.findall("style")), 50)

    def test_real_gtksourceview4_and_5_load_current_colors_by_legacy_id(self):
        for mode, expected in (("dark", "#123456"), ("light", "#d0e0f0")):
            self.render({"dark": "#123456", "light": "#d0e0f0"}, mode)
            for major in ("4", "5"):
                self.assertEqual(self.probe(major), {"name": "Noctalia", "foreground": expected,
                                                    "background": expected})

    def test_all_versioned_lookup_links_point_to_one_mutable_state_file(self):
        links = json.loads(Path(os.environ["GTKSOURCE_LINKS"]).read_text())
        self.assertEqual(len(links), 4)
        for link in links:
            self.assertTrue(Path(link).is_symlink())
            self.assertEqual(os.readlink(link),
                             os.environ["MANAGED_STATE_HOME"] + "/noctalia/gtksourceview/stylix.xml")
        self.assertTrue((self.search / "stylix.xml").is_symlink())

    def test_rendering_and_parser_never_write_editor_preferences(self):
        preference = self.root / "config/gedit/preferences"
        preference.parent.mkdir(parents=True)
        preference.write_text("scheme=stylix\nunrelated=keep\n")
        before = preference.read_bytes()
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.probe("5")
        self.assertEqual(preference.read_bytes(), before)

    def test_bootstrap_and_protected_output_remain_loadable(self):
        placeholder = '<style-scheme id="stylix" _name="Noctalia" version="1.0"></style-scheme>'
        backup = self.root / "original.xml"
        migration.prepare(self.output, backup, placeholder)
        self.assertEqual(self.probe("5")["name"], "Noctalia")
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        before = self.output.read_bytes()
        self.output.chmod(0o444)
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertFalse(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(self.probe("4")["background"], "#123456")


if __name__ == "__main__":
    unittest.main()
