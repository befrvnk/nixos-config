"""Pinned GTK templates/hooks, with isolated XDG dirs and mocked settings tools."""

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class GtkThemeTests(unittest.TestCase):
    def setUp(self):
        self.binary = os.environ["NOCTALIA_BIN"]
        self.assets = Path(os.environ["NOCTALIA_SOURCE"]) / "assets/templates/gtk"
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = self.root / "config"
        self.data = self.root / "data"
        self.environment = dict(os.environ)
        for key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME", "DBUS_SESSION_BUS_ADDRESS"):
            self.environment.pop(key, None)
        self.environment.update(
            HOME=str(self.root),
            XDG_CONFIG_HOME=str(self.config),
            XDG_DATA_HOME=str(self.data),
            XDG_DATA_DIRS=str(self.data),
            XDG_STATE_HOME=str(self.root / "state"),
            XDG_CACHE_HOME=str(self.root / "cache"),
            GSETTINGS_BACKEND="memory",
        )
        self.targets = []
        for version in ("3.0", "4.0"):
            directory = self.config / f"gtk-{version}"
            directory.mkdir(parents=True)
            target = self.root / f"managed-gtk-{version}.css"
            target.write_text('@import url("noctalia.css");\n')
            target.chmod(0o444)
            (directory / "gtk.css").symlink_to(target)
            self.targets.append((directory / "gtk.css", target))
            migration.prepare(directory / "noctalia.css", self.root / f"backup-{version}",
                              "/* Awaiting the native GTK template. */\n")
        for theme in ("adw-gtk3", "adw-gtk3-dark"):
            (self.data / "themes" / theme).mkdir(parents=True)

        tools = self.root / "bin"
        tools.mkdir()
        self.calls = self.root / "settings-calls"
        # Absolute interpreter path also works inside the Nix build sandbox.
        header = f"#!{shutil.which('bash')}\nset -euo pipefail\n"
        (tools / "gsettings").write_text(header + '''
if [ "$1" = list-schemas ]; then
    if [ "${GTK_NO_SCHEMAS:-}" != 1 ]; then
        printf 'org.gnome.desktop.interface\\n'
    fi
elif [ "$1" = set ]; then
    printf 'gsettings %s\\n' "$*" >> "$GTK_SETTINGS_CALLS"
else
    exit 1
fi
''')
        (tools / "dconf").write_text(header + '''
printf 'dconf %s\\n' "$*" >> "$GTK_SETTINGS_CALLS"
''')
        for tool in tools.iterdir():
            tool.chmod(0o755)
        self.environment.update(PATH=f"{tools}:{os.environ['PATH']}",
                                GTK_SETTINGS_CALLS=str(self.calls))

    def apply(self, mode):
        return subprocess.run([shutil.which("bash"), str(self.assets / "apply.sh"), mode],
                              env=self.environment, capture_output=True, text=True, timeout=10)

    def assert_managed_imports_preserved(self):
        for config, target in self.targets:
            self.assertTrue(config.is_symlink())
            self.assertEqual(config.resolve(), target)
            self.assertEqual(target.read_text(), '@import url("noctalia.css");\n')
            self.assertFalse(target.stat().st_mode & stat.S_IWUSR)

    def test_apply_preserves_both_import_symlinks_and_selects_base_theme(self):
        for mode, theme in (("dark", "adw-gtk3-dark"), ("light", "adw-gtk3")):
            with self.subTest(mode=mode):
                result = self.apply(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_managed_imports_preserved()
                self.assertEqual(self.calls.read_text().splitlines()[-1],
                                 f"gsettings set org.gnome.desktop.interface gtk-theme {theme}")
        self.assertNotIn("color-scheme", self.calls.read_text())

    def test_apply_dconf_fallback_does_not_touch_color_scheme(self):
        self.environment["GTK_NO_SCHEMAS"] = "1"
        result = self.apply("dark")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().strip(),
                         "dconf write /org/gnome/desktop/interface/gtk-theme 'adw-gtk3-dark'")
        self.assert_managed_imports_preserved()

    def test_missing_output_fails_without_rewriting_imports_or_setting_theme(self):
        (self.config / "gtk-4.0/noctalia.css").unlink()
        result = self.apply("light")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("GTK4 noctalia.css not found", result.stderr)
        self.assertFalse(self.calls.exists())
        self.assert_managed_imports_preserved()

    def test_css_placeholders_are_valid_and_writable_before_templates_run(self):
        for version in ("3.0", "4.0"):
            output = self.config / f"gtk-{version}/noctalia.css"
            self.assertEqual(output.read_text(), "/* Awaiting the native GTK template. */\n")
            self.assertTrue(output.stat().st_mode & stat.S_IWUSR)
            self.assertFalse(output.is_symlink())

    def test_repeated_activation_keeps_generated_css(self):
        for version in ("3.0", "4.0"):
            output = self.config / f"gtk-{version}/noctalia.css"
            output.write_text("@define-color accent_color #123456;\n")
            inode = output.stat().st_ino
            self.assertFalse(migration.prepare(output, self.root / f"backup-{version}", "/* placeholder */"))
            self.assertEqual(output.stat().st_ino, inode)
            self.assertEqual(output.read_text(), "@define-color accent_color #123456;\n")
        self.assert_managed_imports_preserved()

    def test_pinned_templates_follow_palette_changes_in_both_modes(self):
        # Distinct palettes, not merely a light/dark flip within Catppuccin.
        palettes = (
            {"dark": "#123456", "light": "#d0e0f0"},
            {"dark": "#653412", "light": "#f0e0d0"},
        )
        for version, template_name in (("3.0", "gtk3.css"), ("4.0", "gtk4.css")):
            template = self.assets / template_name
            tokens = set(re.findall(r"colors\.([a-z_]+)\.default\.hex", template.read_text()))
            self.assertIn("primary", tokens)
            self.assertIn("surface", tokens)
            output = self.config / f"gtk-{version}/noctalia.css"
            for index, palette in enumerate(palettes):
                fixture = self.root / "colors.json"
                fixture.write_text(json.dumps({
                    mode: {token: color for token in tokens} for mode, color in palette.items()
                }))
                for mode, expected in palette.items():
                    with self.subTest(version=version, palette=index, mode=mode):
                        result = subprocess.run([
                            self.binary, "theme", "--theme-json", str(fixture), "--both",
                            "--default-mode", mode, "--render", f"{template}:{output}",
                        ], env=self.environment, capture_output=True, text=True, timeout=30)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        rendered = output.read_text()
                        self.assertNotIn("{{", rendered)
                        self.assertIn(f"@define-color accent_color {expected};", rendered)
                        self.assertIn(f"@define-color window_bg_color {expected};", rendered)
                        if version == "4.0":
                            self.assertIn(f"--accent-color: {expected};", rendered)
            self.assert_managed_imports_preserved()


if __name__ == "__main__":
    unittest.main()
