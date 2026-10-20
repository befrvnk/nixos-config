"""Pinned native Niri colors/hook with full generated config validation, no reload."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class NiriThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config_home = self.root / "config"
        self.config_dir = self.config_home / "niri"
        self.config_dir.mkdir(parents=True)
        self.output = self.config_dir / "noctalia.kdl"
        self.config = self.config_dir / "config.kdl"
        self.target = self.root / "managed-config.kdl"
        text = Path(os.environ["NIRI_CONFIG"]).read_text()
        self.assertIn(os.environ["MANAGED_CONFIG_HOME"] + "/niri/noctalia.kdl", text)
        text = text.replace(os.environ["MANAGED_CONFIG_HOME"], str(self.config_home))
        self.target.write_text(text)
        self.target.chmod(0o444)
        self.config.symlink_to(self.target)
        self.assets = Path(os.environ["NOCTALIA_SOURCE"]) / "assets/templates/niri"
        self.environment = dict(os.environ)
        for key in ("NIRI_SOCKET", "NIRI_CONFIG", "NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME"):
            self.environment.pop(key, None)
        self.environment.update(HOME=str(self.root), XDG_CONFIG_HOME=str(self.config_home),
                                XDG_STATE_HOME=str(self.root / "state"),
                                XDG_DATA_HOME=str(self.root / "data"), XDG_CACHE_HOME=str(self.root / "cache"))

    def validate(self, success=True):
        result = subprocess.run([os.environ["NIRI_VALIDATOR"], "validate", "-c", str(self.config)],
                                env=self.environment, capture_output=True, text=True, timeout=15)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def render(self, palette, mode):
        template = self.assets / "niri.kdl"
        tokens = set(re.findall(r"colors\.([a-z_0-9]+)\.default\.hex", template.read_text()))
        fixture = self.root / "colors.json"
        fixture.write_text(json.dumps({
            name: {token: color for token in tokens} for name, color in palette.items()
        }))
        result = subprocess.run([
            os.environ["NOCTALIA_BIN"], "theme", "--theme-json", str(fixture), "--both",
            "--default-mode", mode, "--render", f"{template}:{self.output}",
        ], env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("{{", self.output.read_text())

    def test_pinned_colors_and_full_config_validate_for_two_palettes_and_modes(self):
        before = self.target.read_bytes()
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                with self.subTest(palette=palette, mode=mode):
                    self.render(palette, mode)
                    self.assertRegex(self.output.read_text(), rf'active-color\s+"{expected}"')
                    self.validate()
        self.assertEqual(self.target.read_bytes(), before)
        self.assertTrue(self.config.is_symlink())

    def test_pinned_hook_resolves_output_and_leaves_readonly_config_alone(self):
        before = self.target.read_bytes()
        result = subprocess.run([shutil.which("bash"), str(self.assets / "apply.sh"), "output"],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.output))
        result = subprocess.run([shutil.which("bash"), str(self.assets / "apply.sh"), "apply"],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(self.config.resolve(), self.target)
        self.assertEqual(self.target.read_bytes(), before)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o444)

    def test_generated_structure_keeps_layout_and_color_include_separate(self):
        nodes = json.loads(Path(os.environ["NIRI_NODES"]).read_text())
        include = nodes[-1]
        self.assertEqual(include["name"], "include")
        self.assertEqual(include["properties"], {"optional": True})
        self.assertEqual(include["arguments"], [os.environ["MANAGED_CONFIG_HOME"] + "/niri/noctalia.kdl"])
        layout = next(node for node in nodes if node["name"] == "layout")
        children = {node["name"]: node for node in layout["children"]}
        self.assertEqual(children["gaps"]["arguments"], [12])
        self.assertEqual(children["background-color"]["arguments"], ["transparent"])
        border = {node["name"]: node for node in children["border"]["children"]}
        self.assertEqual(border["width"]["arguments"], [4])
        self.assertNotIn("off", border)
        self.assertNotIn("active-color", border)
        self.assertNotIn("inactive-color", border)
        self.assertIn("off", [node["name"] for node in children["focus-ring"]["children"]])
        self.assertTrue(any(node["name"] == "binds" and node["children"] for node in nodes))
        self.assertTrue(any(node["name"] == "window-rule" for node in nodes))
        template = (self.assets / "niri.kdl").read_text()
        self.assertFalse(re.search(r"^\s*(?:on|off|width|gaps|background-color)\b", template, re.MULTILINE))

    def test_wallpaper_surface_is_only_in_niri_backdrop_not_workspace_previews(self):
        nodes = json.loads(Path(os.environ["NIRI_NODES"]).read_text())
        rules = [node for node in nodes if node["name"] == "layer-rule"]
        wallpaper = [rule for rule in rules if any(
            child["name"] == "match"
            and child["properties"].get("namespace") == "^noctalia-wallpaper$"
            for child in rule["children"])]
        self.assertEqual(len(wallpaper), 1)
        self.assertTrue(any(child["name"] == "place-within-backdrop" and child["arguments"] == [True]
                            for child in wallpaper[0]["children"]))
        self.assertFalse(any(child["properties"].get("namespace") in ("^noctalia-backdrop", "awww-daemon")
                             for rule in rules for child in rule["children"]))

    def test_optional_bootstrap_and_prepared_placeholder_both_validate(self):
        self.validate()  # Missing optional user output must not block Nix builds.
        migration.prepare(self.output, self.root / "backup.kdl", "// Awaiting native colors.\n")
        self.validate()
        self.assertFalse(self.output.is_symlink())

    def test_invalid_included_fragment_is_rejected_even_when_optional(self):
        self.output.write_text('layout { border { active-color "not-a-color"; }; }\n')
        result = self.validate(success=False)
        self.assertIn("color", result.stderr.lower())

    def test_protected_output_is_privatized_without_rewriting_main_config(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        before = self.output.read_bytes()
        self.output.chmod(0o444)
        backup = self.root / "backup.kdl"
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertFalse(migration.prepare(self.output, backup, "unused"))
        self.validate()
        self.assertTrue(self.config.is_symlink())


if __name__ == "__main__":
    unittest.main()
