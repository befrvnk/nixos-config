"""Render pinned Zen CSS without invoking the profile-mutating community hook."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class ZenThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.state = self.root / "state"
        self.runtime = self.state / "noctalia/zen-browser"
        self.runtime.mkdir(parents=True)
        self.source = Path(os.environ["COMMUNITY_TEMPLATE_SOURCE"]) / "zen-browser"
        self.integration = json.loads(Path(os.environ["ZEN_INTEGRATION"]).read_text())
        self.environment = dict(os.environ)
        for key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME", "DBUS_SESSION_BUS_ADDRESS"):
            self.environment.pop(key, None)
        self.environment.update(HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / "config"),
                                XDG_STATE_HOME=str(self.state), XDG_DATA_HOME=str(self.root / "data"),
                                XDG_CACHE_HOME=str(self.root / "cache"))
        self.entries = {}
        for style, key in (("userChrome", "ZEN_CHROME_ENTRY"), ("userContent", "ZEN_CONTENT_ENTRY")):
            entry = Path(os.environ[key]).read_text().replace(os.environ["MANAGED_STATE_HOME"], str(self.state))
            target = self.root / f"managed-{style}.css"
            target.write_text(entry)
            target.chmod(0o444)
            path = self.root / f".zen/default/chrome/{style}.css"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(target)
            self.entries[style] = (path, target, entry)

    def render(self, palette, default_mode):
        for style in ("userChrome", "userContent"):
            template = self.source / f"zen-{style}.css"
            tokens = set(re.findall(r"colors\.([a-z_0-9]+)\.(?:dark|light|default)\.hex",
                                    template.read_text()))
            fixture = self.root / "colors.json"
            fixture.write_text(json.dumps({
                mode: {token: color for token in tokens} for mode, color in palette.items()
            }))
            result = subprocess.run([
                os.environ["NOCTALIA_BIN"], "theme", "--theme-json", str(fixture), "--both",
                "--default-mode", default_mode,
                "--render", f"{template}:{self.runtime / f'zen-{style}.css'}",
            ], env=self.environment, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_both_upstream_styles_render_two_palettes_and_modes(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for default in ("dark", "light"):
                with self.subTest(palette=palette, default=default):
                    self.render(palette, default)
                    for path in self.runtime.iterdir():
                        css = path.read_text()
                        self.assertNotIn("{{", css)
                        for mode, expected in palette.items():
                            self.assertIn(f"@media (prefers-color-scheme: {mode})", css)
                            self.assertRegex(css, rf"--base:\s*{expected};")
                            self.assertRegex(css, rf"--primary:\s*{expected};")
                    self.assertIn("@-moz-document", (self.runtime / "zen-userContent.css").read_text())

    def test_css_contains_both_modes_independently_of_active_mode(self):
        palette = {"dark": "#123456", "light": "#d0e0f0"}
        self.render(palette, "dark")
        before = {path.name: path.read_bytes() for path in self.runtime.iterdir()}
        self.render(palette, "light")
        self.assertEqual({path.name: path.read_bytes() for path in self.runtime.iterdir()}, before)

    def test_managed_imports_and_noncolor_layout_are_preserved(self):
        for style, (path, target, entry) in self.entries.items():
            self.assertEqual(entry.splitlines()[0],
                             f'@import url("file://{self.runtime}/zen-{style}.css");')
            self.assertTrue(path.is_symlink())
            self.assertEqual(path.resolve(), target)
            self.assertEqual(target.stat().st_mode & 0o777, 0o444)
            self.assertNotIn("Catppuccin", entry)
        content = self.entries["userContent"][2]
        self.assertIn("82px", content)
        self.assertIn("64px", content)
        self.assertIn("max-width: 609px", content)
        for kind in ("chrome", "content"):
            registration = self.integration[kind]
            self.assertEqual(set(registration), {"input_path", "output_path"})
            self.assertTrue(registration["output_path"].startswith("$XDG_STATE_HOME/"))
            self.assertTrue(registration["input_path"].endswith(
                "/zen-browser/zen-userChrome.css" if kind == "chrome" else "/zen-browser/zen-userContent.css"))

    def test_browser_policies_and_launcher_remain_protected(self):
        policies = self.integration["policies"]
        preferences = policies["Preferences"]
        self.assertEqual(preferences["toolkit.legacyUserProfileCustomizations.stylesheets"],
                         {"Value": True, "Status": "locked"})
        self.assertNotIn("devtools.chrome.enabled", preferences)
        for key in ("signon.rememberSignons", "signon.autofillForms", "signon.formlessCapture.enabled",
                    "signon.generation.enabled"):
            self.assertEqual(preferences[key], {"Value": False, "Status": "locked"})
        self.assertFalse(policies["PasswordManagerEnabled"])
        self.assertTrue(policies["EnableTrackingProtection"]["Locked"])
        for guid in ("uBlock0@raymondhill.net", "{d634138d-c276-4fc8-924b-40a0ea21d284}"):
            self.assertEqual(policies["ExtensionSettings"][guid]["installation_mode"], "force_installed")
        self.assertEqual(self.integration["launcher"], "zen-launch %U")

    def test_launcher_uses_the_package_with_actual_declared_policies(self):
        launcher = Path(os.environ["ZEN_LAUNCHER"]).read_text()
        self.assertIn(f'exec {os.environ["ZEN_PACKAGE_BIN"]} -P "Default Profile" "$@"', launcher)
        policies = list(Path(os.environ["ZEN_POLICY_PACKAGE"]).glob("lib/*/distribution/policies.json"))
        self.assertEqual(len(policies), 1)
        installed = json.loads(policies[0].read_text())["policies"]
        for key, expected in self.integration["policies"].items():
            self.assertEqual(installed[key], expected, key)

    def test_rendering_does_not_modify_profile_imports_preferences_or_backups(self):
        profiles = [self.root / ".zen/default", self.root / ".zen/default-backup",
                    self.root / "config/zen/unmanaged"]
        tracked = {}
        for profile in profiles:
            profile.mkdir(parents=True, exist_ok=True)
            for name in ("user.js", "prefs.js", "profiles.ini"):
                path = profile / name
                path.write_text(f"unrelated {name}\n")
                tracked[path] = path.read_bytes()
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.render({"dark": "#653412", "light": "#f0e0d0"}, "light")
        for path, before in tracked.items():
            self.assertEqual(path.read_bytes(), before)
        for path, target, before in self.entries.values():
            self.assertTrue(path.is_symlink())
            self.assertEqual(target.read_text(), before)
        self.assertFalse((self.root / "cache/noctalia/zen-browser").exists())

    def test_runtime_bootstrap_and_protected_output_are_safe(self):
        for style in ("userChrome", "userContent"):
            path = self.runtime / f"zen-{style}.css"
            backup = self.root / f"backup-{style}.css"
            migration.prepare(path, backup, "/* Awaiting Noctalia. */")
            self.assertEqual(path.read_text(), "/* Awaiting Noctalia. */")
            path.write_text("/* Legacy output. */")
            path.chmod(0o444)
            self.assertTrue(migration.prepare(path, backup, "unused"))
            self.assertEqual(backup.read_text(), "/* Legacy output. */")
            self.assertEqual(path.stat().st_mode & 0o777, 0o644)
            self.assertFalse(migration.prepare(path, backup, "unused"))


if __name__ == "__main__":
    unittest.main()
