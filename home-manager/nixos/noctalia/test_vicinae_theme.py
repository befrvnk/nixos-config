"""Reviewed upstream template/hook with the real pinned Vicinae theme parser."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class VicinaeThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = Path(os.environ["COMMUNITY_TEMPLATE_SOURCE"]) / "vicinae"
        self.output = self.root / "data/vicinae/themes/noctalia.toml"
        self.output.parent.mkdir(parents=True)
        self.icon = self.output.with_suffix(".svg")
        self.icon_source = Path(os.environ["NOCTALIA_SOURCE"]) / "assets/noctalia.svg"
        self.environment = dict(os.environ)
        for key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME", "VICINAE_OVERRIDES"):
            self.environment.pop(key, None)
        self.environment.update(
            HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_DATA_HOME=str(self.root / "data"), XDG_STATE_HOME=str(self.root / "state"),
            XDG_CACHE_HOME=str(self.root / "cache"),
            DBUS_SESSION_BUS_ADDRESS=f"unix:path={self.root}/no-bus",
        )
        # Never send IPC to a user's launcher or start another server.
        tools = self.root / "bin"
        tools.mkdir()
        self.calls = self.root / "vicinae-calls"
        (tools / "vicinae").write_text(
            f"#!{shutil.which('bash')}\n" + 'printf "%s\\n" "$*" >> "$VICINAE_TEST_CALLS"\n')
        (tools / "vicinae").chmod(0o755)
        self.environment.update(PATH=f"{tools}:{os.environ['PATH']}",
                                VICINAE_TEST_CALLS=str(self.calls))

    def apply(self):
        result = subprocess.run([
            shutil.which("bash"), str(self.source / "apply.sh"), str(self.icon_source),
        ], env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def parse(self):
        result = subprocess.run([os.environ["VICINAE_PROBE"], str(self.output)],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def render(self, palette, mode):
        template = self.source / "vicinae.toml"
        tokens = set(re.findall(r"colors\.([a-z_]+)\.default\.hex", template.read_text()))
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

    def test_reviewed_template_parses_two_palettes_in_both_modes(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                with self.subTest(palette=palette, mode=mode):
                    self.render(palette, mode)
                    self.apply()
                    theme = self.parse()
                    self.assertEqual(theme["id"], "noctalia")
                    self.assertEqual(theme["variant"], mode)
                    self.assertEqual(theme["name"], "Noctalia")
                    self.assertEqual(theme["diagnostics"], [])
                    for field in ("background", "foreground", "accent"):
                        self.assertEqual(theme[field], expected)
        self.assertTrue(all(line == "theme set noctalia" for line in self.calls.read_text().splitlines()))

    def test_native_reload_selector_matches_both_declarative_modes(self):
        settings = json.loads(Path(os.environ["VICINAE_SETTINGS"]).read_text())
        for mode in ("dark", "light"):
            self.assertEqual(settings["theme"][mode]["name"], "noctalia")
            self.assertEqual(settings["theme"][mode]["icon_theme"], "Papirus")
        self.apply()
        self.assertEqual(self.calls.read_text(), "theme set noctalia\n")

    def test_apply_preserves_existing_readonly_icon_and_config_files(self):
        self.icon.write_text("original legacy icon")
        self.icon.chmod(0o444)
        config = self.root / "config/vicinae"
        config.mkdir(parents=True)
        managed = self.root / "declarative-settings.json"
        managed.write_text(Path(os.environ["VICINAE_SETTINGS"]).read_text())
        managed.chmod(0o444)
        (config / "nix.json").symlink_to(managed)
        user = config / "settings.json"
        user.write_text('{"unrelated":true}\n')
        before = managed.read_bytes()
        self.apply()
        self.assertEqual(self.icon.read_text(), "original legacy icon")
        self.assertEqual(self.icon.stat().st_mode & 0o777, 0o444)
        self.assertTrue((config / "nix.json").is_symlink())
        self.assertEqual(managed.read_bytes(), before)
        self.assertEqual(user.read_text(), '{"unrelated":true}\n')

    def test_apply_installs_missing_icon_without_overwrite_on_repeat(self):
        self.apply()
        self.assertEqual(self.icon.read_bytes(), self.icon_source.read_bytes())
        before = self.icon.stat().st_ino
        self.apply()
        self.assertEqual(self.icon.stat().st_ino, before)

    def test_placeholder_uses_builtin_inheritance_until_first_render(self):
        migration.prepare(self.output, self.root / "backup.toml", '''[meta]
name = "Noctalia"
description = "Awaiting native template"
variant = "dark"
inherits = "vicinae-dark"
''')
        theme = self.parse()
        self.assertEqual(theme["id"], "noctalia")
        self.assertEqual(theme["variant"], "dark")
        self.assertEqual(theme["diagnostics"], [])
        self.assertTrue(re.fullmatch(r"#[0-9a-f]{6}", theme["background"]))

    def test_protected_output_migration_preserves_rendered_theme_and_backup(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.apply()
        before = self.output.read_bytes()
        self.output.chmod(0o444)
        backup = self.root / "backup.toml"
        self.assertTrue(migration.prepare(self.output, backup, "unused placeholder"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertFalse(migration.prepare(self.output, backup, "unused placeholder"))
        self.assertEqual(self.parse()["background"], "#123456")


if __name__ == "__main__":
    unittest.main()
