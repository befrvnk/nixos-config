"""Pinned community colors plus the official declarative VS Code theme extension.

CLI discovery uses temporary HOME/user-data/extension dirs; never opens an editor.
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


class VscodeThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "state/noctalia/vscode/NoctaliaTheme-color-theme.json"
        self.output.parent.mkdir(parents=True)
        self.source = Path(os.environ["COMMUNITY_TEMPLATE_SOURCE"]) / "vscode/vscode.json"
        self.extension = Path(os.environ["VSCODE_EXTENSION"])
        self.settings_source = Path(os.environ["VSCODE_SETTINGS"])
        self.settings = json.loads(self.settings_source.read_text())
        self.registration = json.loads(Path(os.environ["VSCODE_TEMPLATE"]).read_text())
        self.environment = dict(os.environ)
        for key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME", "DBUS_SESSION_BUS_ADDRESS",
                    "VSCODE_IPC_HOOK_CLI", "VSCODE_PORTABLE", "VSCODE_EXTENSIONS"):
            self.environment.pop(key, None)
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700)
        self.environment.update(
            HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_DATA_HOME=str(self.root / "data"), XDG_STATE_HOME=str(self.root / "state"),
            XDG_CACHE_HOME=str(self.root / "cache"), XDG_RUNTIME_DIR=str(runtime),
            DISPLAY="", WAYLAND_DISPLAY="", DO_NOT_TRACK="1",
            DBUS_SESSION_BUS_ADDRESS=f"unix:path={runtime}/no-bus",
        )

    def render(self, palette, mode):
        tokens = set(re.findall(r"colors\.([a-z_0-9]+)\.default\.hex", self.source.read_text()))
        self.assertIn("background", tokens)
        fixture = self.root / "colors.json"
        fixture.write_text(json.dumps({
            name: {token: color for token in tokens} for name, color in palette.items()
        }))
        result = subprocess.run([
            os.environ["NOCTALIA_BIN"], "theme", "--theme-json", str(fixture), "--both",
            "--default-mode", mode, "--render", f"{self.source}:{self.output}",
        ], env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("{{", self.output.read_text())
        return json.loads(self.output.read_text())

    def test_official_extension_manifest_is_theme_only_and_data_is_external(self):
        manifest = json.loads((self.extension / "package.json").read_text())
        self.assertEqual(manifest["publisher"].lower(), "noctalia")
        self.assertEqual(manifest["name"], "noctaliatheme")
        self.assertEqual(manifest["version"], "0.0.5")
        self.assertNotIn("main", manifest)
        self.assertNotIn("activationEvents", manifest)
        contribution = manifest["contributes"]["themes"][0]
        self.assertEqual(contribution["label"], self.settings["workbench.colorTheme"])
        self.assertEqual(contribution["uiTheme"], "vs-dark")
        theme = self.extension / contribution["path"]
        self.assertTrue(theme.is_symlink())
        self.assertEqual(os.readlink(theme),
                         os.environ["MANAGED_STATE_HOME"] + "/noctalia/vscode/NoctaliaTheme-color-theme.json")
        self.assertFalse((self.extension / "package.json").stat().st_mode & 0o222)

    def test_pinned_colors_follow_two_palettes_in_both_modes(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                with self.subTest(palette=palette, mode=mode):
                    theme = self.render(palette, mode)
                    self.assertEqual(theme["name"], "NoctaliaTheme")
                    # Preserve/document upstream's single dark-classified theme.
                    self.assertEqual(theme["type"], "dark")
                    self.assertEqual(theme["colors"]["editor.background"], expected)
                    self.assertEqual(theme["colors"]["editor.foreground"], expected)
                    self.assertTrue(theme["tokenColors"])
                    self.assertTrue(theme["semanticHighlighting"])
                    self.assertTrue(theme["semanticTokenColors"])

    def test_actual_cli_discovers_the_declarative_extension(self):
        extensions = self.root / "extensions"
        extensions.mkdir()
        (extensions / "noctalia.noctaliatheme").symlink_to(self.extension, target_is_directory=True)
        # The packaged CLI script uses /usr/bin/env, absent in the build sandbox.
        # Run that unmodified script with the Nix shell, without opening Electron UI.
        cli_script = Path(os.environ["VSCODE_CLI"]).with_name(".code-wrapped")
        result = subprocess.run([
            shutil.which("bash"), str(cli_script), "--extensions-dir", str(extensions),
            "--user-data-dir", str(self.root / "user-data"),
            "--list-extensions", "--show-versions",
        ], env=self.environment, capture_output=True, text=True, timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("noctalia.noctaliatheme@0.0.5", result.stdout.lower())

    def test_managed_settings_keep_font_intent_and_disable_competing_updates(self):
        self.assertEqual(self.settings["workbench.colorTheme"], "NoctaliaTheme")
        self.assertFalse(self.settings["window.autoDetectColorScheme"])
        self.assertFalse(self.settings["extensions.autoUpdate"])
        self.assertEqual(self.settings["update.mode"], "none")
        self.assertFalse(self.settings["extensions.autoCheckUpdates"])
        self.assertEqual(self.settings["editor.fontFamily"], "JetBrainsMono Nerd Font")
        self.assertEqual(self.settings["chat.fontFamily"], "Noto Sans")
        self.assertAlmostEqual(self.settings["editor.fontSize"], 11 * 4 / 3)
        self.assertAlmostEqual(self.settings["terminal.integrated.fontSize"], 11 * 4 / 3)
        self.assertEqual(set(self.registration), {"input_path", "output_path"})
        self.assertEqual(self.registration["output_path"],
                         "$XDG_STATE_HOME/noctalia/vscode/NoctaliaTheme-color-theme.json")

    def test_rendering_keeps_settings_and_extension_metadata_unchanged(self):
        settings = self.settings_source.read_bytes()
        manifest = (self.extension / "package.json").read_bytes()
        link = os.readlink(self.extension / "themes/NoctaliaTheme-color-theme.json")
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.render({"dark": "#653412", "light": "#f0e0d0"}, "light")
        self.assertEqual(self.settings_source.read_bytes(), settings)
        self.assertEqual((self.extension / "package.json").read_bytes(), manifest)
        self.assertEqual(os.readlink(self.extension / "themes/NoctaliaTheme-color-theme.json"), link)

    def test_bootstrap_and_legacy_output_are_writable_without_store_changes(self):
        placeholder = json.dumps({"name": "NoctaliaTheme", "type": "dark", "colors": {}, "tokenColors": []})
        backup = self.root / "original.json"
        migration.prepare(self.output, backup, placeholder)
        self.assertEqual(json.loads(self.output.read_text())["name"], "NoctaliaTheme")
        self.output.chmod(0o444)
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_text(), placeholder)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o644)
        self.assertFalse(migration.prepare(self.output, backup, "unused"))


if __name__ == "__main__":
    unittest.main()
