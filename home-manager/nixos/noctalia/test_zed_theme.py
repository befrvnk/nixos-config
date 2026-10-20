"""Pinned Zed family rendering and the actual Home Manager settings merger.

Uses temporary XDG directories; never launches Zed or rewrites user settings.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class ZedThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = self.root / "config"
        self.output = self.config / "zed/themes/noctalia.json"
        self.output.parent.mkdir(parents=True)
        self.template = Path(os.environ["COMMUNITY_TEMPLATE_SOURCE"]) / "zed/zed.json"
        self.settings = json.loads(Path(os.environ["ZED_SETTINGS"]).read_text())
        self.environment = dict(os.environ)
        for key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME", "DBUS_SESSION_BUS_ADDRESS"):
            self.environment.pop(key, None)
        self.environment.update(HOME=str(self.root), XDG_CONFIG_HOME=str(self.config),
                                XDG_DATA_HOME=str(self.root / "data"),
                                XDG_STATE_HOME=str(self.root / "state"),
                                XDG_CACHE_HOME=str(self.root / "cache"))

    def render(self, palette, default_mode):
        tokens = set(re.findall(r"colors\.([a-z_0-9]+)\.(?:dark|light|default)\.hex",
                                self.template.read_text()))
        self.assertIn("background", tokens)
        fixture = self.root / "colors.json"
        fixture.write_text(json.dumps({
            mode: {token: color for token in tokens} for mode, color in palette.items()
        }))
        result = subprocess.run([
            os.environ["NOCTALIA_BIN"], "theme", "--theme-json", str(fixture), "--both",
            "--default-mode", default_mode, "--render", f"{self.template}:{self.output}",
        ], env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("{{", self.output.read_text())
        return json.loads(self.output.read_text())

    def merge_settings(self):
        # Execute HM's generated merger, not a reimplementation. Substitute the
        # target directory before running so no path points to the real home.
        body = Path(os.environ["ZED_SETTINGS_ACTIVATION"]).read_text()
        self.assertIn(os.environ["MANAGED_CONFIG_HOME"] + "/zed/settings.json", body)
        body = body.replace(os.environ["MANAGED_CONFIG_HOME"], str(self.config))
        self.assertNotIn(os.environ["MANAGED_CONFIG_HOME"], body)
        result = subprocess.run([shutil.which("bash"), "-eu", "-c", body],
                                env=self.environment, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads((self.config / "zed/settings.json").read_text())

    def test_upstream_family_renders_two_palettes_and_all_four_variants(self):
        expected_names = {
            "Noctalia Dark", "Noctalia Light",
            "Noctalia Dark Transparent", "Noctalia Light Transparent",
        }
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for default in ("dark", "light"):
                with self.subTest(palette=palette, default=default):
                    family = self.render(palette, default)
                    self.assertEqual(family["name"], "Noctalia")
                    self.assertEqual({theme["name"] for theme in family["themes"]}, expected_names)
                    for theme in family["themes"]:
                        expected = palette[theme["appearance"]]
                        appearance = "transparent" if "Transparent" in theme["name"] else "opaque"
                        self.assertTrue(theme["style"]["background"].startswith(expected))
                        editor_background = "#00000000" if appearance == "transparent" else expected
                        self.assertEqual(theme["style"]["editor.background"], editor_background)
                        self.assertEqual(theme["style"]["editor.foreground"], expected)
                        self.assertEqual(theme["style"]["background.appearance"], appearance)
                        self.assertTrue(theme["style"]["syntax"])
                    for mode in ("dark", "light"):
                        self.assertIn(self.settings["theme"][mode], expected_names)

    def test_family_bytes_do_not_depend_on_active_mode(self):
        palette = {"dark": "#123456", "light": "#d0e0f0"}
        self.render(palette, "dark")
        before = self.output.read_bytes()
        self.render(palette, "light")
        self.assertEqual(self.output.read_bytes(), before)

    def test_actual_settings_merger_preserves_unrelated_user_preferences(self):
        target = self.config / "zed/settings.json"
        target.write_text('''{
// Mutable user preferences must survive the managed theme change.
"theme": "Base16 Catppuccin Latte",
"icon_theme": "Catppuccin Mocha",
"auto_install_extensions": {"python": true},
"languages": {"Python": {"language_servers": ["ruff"]}}
}''')
        target.chmod(0o600)
        merged = self.merge_settings()
        self.assertEqual(merged["theme"], {
            "mode": "system", "dark": "Noctalia Dark", "light": "Noctalia Light",
        })
        self.assertEqual(merged["icon_theme"], "Catppuccin Mocha")
        self.assertTrue(merged["auto_install_extensions"]["python"])
        self.assertTrue(merged["auto_install_extensions"]["nix"])
        self.assertEqual(merged["languages"]["Python"]["language_servers"], ["ruff"])
        self.assertEqual(merged["buffer_font_family"], "JetBrainsMono Nerd Font")
        self.assertEqual(merged["ui_font_family"], "Noto Sans")
        self.assertAlmostEqual(merged["buffer_font_size"], 11 * 4 / 3)
        self.assertAlmostEqual(merged["ui_font_size"], 11 * 4 / 3)
        self.assertFalse(merged["tab_bar"]["show"])
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.merge_settings(), merged)

    def test_rendering_never_changes_editor_settings(self):
        self.merge_settings()
        target = self.config / "zed/settings.json"
        before = target.read_bytes()
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.render({"dark": "#653412", "light": "#f0e0d0"}, "light")
        self.assertEqual(target.read_bytes(), before)

    def test_protected_runtime_family_is_backed_up_and_kept_on_activation(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        before = self.output.read_bytes()
        self.output.chmod(0o444)
        backup = self.root / "original.json"
        self.assertTrue(migration.prepare(self.output, backup, "{}"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertFalse(migration.prepare(self.output, backup, "{}"))
        self.assertEqual(self.output.read_bytes(), before)

    def test_bootstrap_family_exposes_the_declarative_selectors(self):
        placeholder = json.dumps({"name": "Noctalia", "author": "Noctalia", "themes": [
            {"name": self.settings["theme"][mode], "appearance": mode, "style": {}}
            for mode in ("dark", "light")
        ]})
        migration.prepare(self.output, self.root / "backup.json", placeholder)
        self.assertEqual(len(json.loads(self.output.read_text())["themes"]), 2)
        self.assertFalse(self.output.is_symlink())
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o644)


if __name__ == "__main__":
    unittest.main()
