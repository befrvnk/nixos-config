"""Shipped Starship palette composed with the managed base, using the real CLI."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import tomllib
import unittest

import prepare_theme_output as migration


class StarshipThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "state/noctalia/starship.toml"
        self.output.parent.mkdir(parents=True)
        self.template = Path(os.environ["STARSHIP_TEMPLATE"])
        self.base = Path(os.environ["STARSHIP_BASE"])
        self.environment = dict(os.environ)
        self.environment.update(
            HOME=str(self.root), STARSHIP_CONFIG=str(self.output),
            STARSHIP_CACHE=str(self.root / "cache/starship"), STARSHIP_SHELL="nu",
            XDG_CONFIG_HOME=str(self.root / "config"), XDG_STATE_HOME=str(self.root / "state"),
            XDG_DATA_HOME=str(self.root / "data"), XDG_CACHE_HOME=str(self.root / "cache"),
            TERM="xterm-256color", COLORTERM="truecolor",
        )

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
        return tomllib.loads(self.output.read_text())

    def character(self):
        result = subprocess.run([os.environ["STARSHIP_CLI"], "module", "character", "--status", "0"],
                                cwd=self.root, env=self.environment,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Error", result.stderr)
        self.assertIn("❯", result.stdout)
        return result.stdout

    def test_native_palette_is_unmodified_and_managed_base_is_the_prefix(self):
        shipped = Path(os.environ["NOCTALIA_SOURCE"]) / "assets/templates/starship/starship.toml"
        self.assertTrue(self.template.read_bytes().endswith(shipped.read_bytes()))
        self.assertTrue(self.template.read_bytes().startswith(self.base.read_bytes()))
        self.assertEqual(tomllib.loads(self.base.read_text())["palette"], "noctalia")
        self.assertFalse(self.base.stat().st_mode & 0o222)

    def test_two_palettes_and_modes_parse_as_complete_starship_configs(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                result = self.render(palette, mode)
                self.assertEqual(result["palette"], "noctalia")
                self.assertEqual(result["palettes"]["noctalia"]["green"], expected)
                self.assertEqual(result["palettes"]["noctalia"]["text"], expected)
                self.assertNotIn("base16", result.get("palettes", {}))
                for key, value in tomllib.loads(self.base.read_text()).items():
                    if key == "palettes":
                        for name, palette_values in value.items():
                            self.assertEqual(result[key][name], palette_values)
                    else:
                        self.assertEqual(result[key], value)

    def test_real_starship_prompt_uses_latest_rgb_palette(self):
        for mode, expected in (("dark", "#123456"), ("light", "#d0e0f0")):
            self.render({"dark": "#123456", "light": "#d0e0f0"}, mode)
            rgb = tuple(int(expected[i:i+2], 16) for i in (1, 3, 5))
            self.assertIn(";2;%d;%d;%d" % rgb, self.character())

    def test_native_config_printing_and_pointers_do_not_write_the_base(self):
        before = self.base.read_bytes()
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        result = subprocess.run([os.environ["STARSHIP_CLI"], "print-config", "palette"],
                                cwd=self.root, env=self.environment,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("noctalia", result.stdout)
        self.assertEqual(self.base.read_bytes(), before)
        pointers = json.loads(Path(os.environ["STARSHIP_POINTERS"]).read_text())
        self.assertEqual(pointers["session"], os.environ["MANAGED_STATE_HOME"] + "/noctalia/starship.toml")
        self.assertEqual(pointers["nushell"], pointers["session"])
        self.assertEqual(set(pointers["entry"]), {"input_path", "output_path"})

    def test_bootstrap_keeps_starship_functional_before_first_palette(self):
        migration.prepare(self.output, self.root / "backup.toml", "# Awaiting native palette.\n")
        self.assertEqual(tomllib.loads(self.output.read_text()), {})
        self.character()

    def test_protected_runtime_config_is_preserved_and_backed_up(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        before = self.output.read_bytes()
        self.output.chmod(0o444)
        backup = self.root / "backup.toml"
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertFalse(migration.prepare(self.output, backup, "unused"))
        self.character()


if __name__ == "__main__":
    unittest.main()
