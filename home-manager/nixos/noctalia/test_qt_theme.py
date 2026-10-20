"""Use the pinned stock Qt template and real Qt5/Qt6 plugins, without a display."""

import configparser
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class QtThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = self.root / "config"
        self.template = Path(os.environ["NOCTALIA_SOURCE"]) / "assets/templates/qt/qtct.conf"
        self.environment = dict(os.environ)
        for key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME", "QT_STYLE_OVERRIDE"):
            self.environment.pop(key, None)
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700)
        self.environment.update(
            HOME=str(self.root), XDG_CONFIG_HOME=str(self.config),
            XDG_DATA_HOME=str(self.root / "data"), XDG_DATA_DIRS=str(self.root / "data"),
            XDG_STATE_HOME=str(self.root / "state"), XDG_CACHE_HOME=str(self.root / "cache"),
            XDG_RUNTIME_DIR=str(runtime), DISPLAY="", WAYLAND_DISPLAY="",
            DBUS_SESSION_BUS_ADDRESS=f"unix:path={runtime}/no-bus",
            QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="qt5ct",
        )
        self.targets = {}
        for major in ("5", "6"):
            directory = self.config / f"qt{major}ct"
            output = directory / "colors/noctalia.conf"
            migration.prepare(output, self.root / f"backup-{major}", "[ColorScheme]\n")
            source = Path(os.environ[f"QT{major}_CONFIG_SOURCE"]).read_text()
            source = source.replace(os.environ["QT_CONFIG_HOME"], str(self.config))
            target = self.root / f"managed-qt{major}ct.conf"
            target.write_text(source)
            target.chmod(0o444)
            (directory / f"qt{major}ct.conf").symlink_to(target)
            self.targets[major] = (target, source)

    def render(self, output, palette, mode):
        tokens = set(re.findall(r"colors\.([a-z_]+)\.default\.hex", self.template.read_text()))
        fixture = self.root / "colors.json"
        fixture.write_text(json.dumps({
            name: {token: color for token in tokens} for name, color in palette.items()
        }))
        result = subprocess.run([
            os.environ["NOCTALIA_BIN"], "theme", "--theme-json", str(fixture), "--both",
            "--default-mode", mode, "--render", f"{self.template}:{output}",
        ], env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("{{", output.read_text())

    def probe(self, major):
        environment = dict(self.environment, QT_PLUGIN_PATH=os.environ[f"QT{major}_PLUGIN_PATH"])
        result = subprocess.run([os.environ[f"QT{major}_PROBE"]], env=environment,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout.strip().splitlines()[-1])

    def assert_main_configs_preserved(self):
        for major, (target, contents) in self.targets.items():
            config = self.config / f"qt{major}ct/qt{major}ct.conf"
            self.assertTrue(config.is_symlink())
            self.assertEqual(config.resolve(), target)
            self.assertEqual(target.read_text(), contents)
            self.assertEqual(target.stat().st_mode & 0o777, 0o444)

    def test_real_plugins_follow_two_palettes_in_both_modes(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                for major in ("5", "6"):
                    with self.subTest(major=major, palette=palette, mode=mode):
                        output = self.config / f"qt{major}ct/colors/noctalia.conf"
                        self.render(output, palette, mode)
                        actual = self.probe(major)
                        self.assertTrue(actual["qt"].startswith(major + "."))
                        self.assertEqual(actual["window"], expected, actual)
                        self.assertEqual(actual["foreground"], expected, actual)
                        self.assertEqual(actual["highlight"], expected, actual)
                        self.assertEqual(actual["base_style"].lower(), "fusion", actual)
                        self.assertEqual(actual["font"], "Noto Sans", actual)
                        self.assertEqual(actual["fixed_font"], "JetBrainsMono Nerd Font", actual)
                        self.assertEqual(actual["icons"], "Papirus", actual)
        self.assert_main_configs_preserved()

    def test_stock_palette_role_count_is_compatible_with_both_versions(self):
        for major in ("5", "6"):
            output = self.config / f"qt{major}ct/colors/noctalia.conf"
            self.render(output, {"dark": "#123456", "light": "#d0e0f0"}, "dark")
            parser = configparser.ConfigParser()
            parser.read(output)
            for group in ("active_colors", "disabled_colors", "inactive_colors"):
                colors = [color.strip() for color in parser["ColorScheme"][group].split(",")]
                # Qt5 uses the first 21; Qt6 also has the accent role at index 21.
                self.assertEqual(len(colors), 22)
                self.assertTrue(all(re.fullmatch(r"#[0-9a-fA-F]{6}", color) for color in colors))
        self.assert_main_configs_preserved()

    def test_bootstrap_without_rendered_colors_does_not_crash(self):
        for major in ("5", "6"):
            self.assertIn("window", self.probe(major))
        self.assert_main_configs_preserved()

    def test_readonly_legacy_palette_is_backed_up_then_writable(self):
        for major in ("5", "6"):
            output = self.config / f"qt{major}ct/colors/noctalia.conf"
            self.render(output, {"dark": "#123456", "light": "#d0e0f0"}, "dark")
            before = output.read_bytes()
            output.chmod(0o444)
            backup = self.root / f"legacy-{major}.conf"
            self.assertTrue(migration.prepare(output, backup, "[ColorScheme]\n"))
            self.assertEqual(backup.read_bytes(), before)
            self.assertFalse(migration.prepare(output, backup, "[ColorScheme]\n"))
            self.assertEqual(self.probe(major)["window"], "#123456")
        self.assert_main_configs_preserved()


if __name__ == "__main__":
    unittest.main()
