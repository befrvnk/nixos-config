"""Writable-output migration and pinned built-in Ghostty integration tests.

No running Ghostty process is signalled: the apply hook uses a fake reload.sh,
while template rendering uses the offline Noctalia CLI in isolated XDG dirs.
"""

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

import prepare_ghostty_theme as migration


class PrepareGhosttyThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.theme = self.root / "themes/noctalia"
        self.backup = self.root / "state/ghostty-theme.pre-template"
        self.theme.parent.mkdir()

    def test_new_output_is_valid_writable_placeholder(self):
        self.assertTrue(migration.prepare(self.theme, self.backup))
        self.assertEqual(self.theme.read_text(), migration.PLACEHOLDER)
        self.assertTrue(self.theme.stat().st_mode & stat.S_IWUSR)
        self.assertFalse(self.backup.exists())

    def test_readonly_file_is_backed_up_and_made_private_writable(self):
        self.theme.write_text("original colors\n")
        self.theme.chmod(0o444)
        self.assertTrue(migration.prepare(self.theme, self.backup))
        self.assertEqual(self.theme.read_text(), "original colors\n")
        self.assertEqual(self.backup.read_text(), "original colors\n")
        self.assertTrue(self.theme.stat().st_mode & stat.S_IWUSR)
        self.assertEqual(self.backup.stat().st_mode & 0o777, 0o600)

    def test_writable_output_is_not_replaced(self):
        self.theme.write_text("runtime colors\n")
        inode = self.theme.stat().st_ino
        self.assertFalse(migration.prepare(self.theme, self.backup))
        self.assertEqual(self.theme.stat().st_ino, inode)
        self.assertEqual(self.theme.read_text(), "runtime colors\n")
        self.assertFalse(self.backup.exists())

    def test_symlink_target_is_not_chmodded_or_modified(self):
        target = self.root / "readonly-source"
        target.write_text("source colors\n")
        target.chmod(0o444)
        self.theme.symlink_to(target)
        self.assertTrue(migration.prepare(self.theme, self.backup))
        self.assertFalse(self.theme.is_symlink())
        self.theme.write_text("new runtime colors\n")
        self.assertEqual(target.read_text(), "source colors\n")
        self.assertFalse(target.stat().st_mode & stat.S_IWUSR)
        self.assertEqual(self.backup.read_text(), "source colors\n")

    def test_hardlink_is_detached_before_runtime_writes(self):
        target = self.root / "hardlink-source"
        target.write_text("source colors\n")
        os.link(target, self.theme)
        migration.prepare(self.theme, self.backup)
        self.theme.write_text("new colors\n")
        self.assertEqual(target.read_text(), "source colors\n")
        self.assertNotEqual(target.stat().st_ino, self.theme.stat().st_ino)

    def test_repeated_activation_keeps_original_backup(self):
        self.theme.write_text("original\n")
        self.theme.chmod(0o444)
        migration.prepare(self.theme, self.backup)
        self.theme.write_text("later colors\n")
        self.theme.chmod(0o444)
        migration.prepare(self.theme, self.backup)
        self.assertEqual(self.backup.read_text(), "original\n")
        self.assertEqual(self.theme.read_text(), "later colors\n")

    def test_store_parent_is_rejected_without_writing(self):
        with self.assertRaises(ValueError):
            migration.prepare(Path("/nix/store/test-immutable/themes/noctalia"), self.backup)
        self.assertFalse(self.backup.exists())

    def test_directory_and_dangling_link_are_not_replaced(self):
        self.theme.mkdir()
        with self.assertRaises(ValueError):
            migration.prepare(self.theme, self.backup)
        self.theme.rmdir()
        self.theme.symlink_to(self.root / "missing")
        with self.assertRaises(ValueError):
            migration.prepare(self.theme, self.backup)
        self.assertTrue(self.theme.is_symlink())


class BuiltinGhosttyTemplateTests(unittest.TestCase):
    def setUp(self):
        self.binary = os.environ["NOCTALIA_BIN"]
        self.assets = Path(os.environ["NOCTALIA_SOURCE"]) / "assets/templates/ghostty"
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.environment = dict(os.environ)
        for key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME", "DBUS_SESSION_BUS_ADDRESS"):
            self.environment.pop(key, None)
        self.environment.update(
            HOME=str(self.root),
            XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_STATE_HOME=str(self.root / "state"),
            XDG_CACHE_HOME=str(self.root / "cache"),
        )

    def test_pinned_template_renders_both_modes(self):
        template = self.assets / "ghostty"
        tokens = set(re.findall(r"colors\.([a-z_]+)\.default\.hex", template.read_text()))
        self.assertGreaterEqual(len(tokens), 22)
        fixture = self.root / "colors.json"
        fixture.write_text(json.dumps({
            "dark": {token: "#102030" for token in tokens},
            "light": {token: "#d0e0f0" for token in tokens},
        }))
        for mode, expected in (("dark", "#102030"), ("light", "#d0e0f0")):
            with self.subTest(mode=mode):
                output = self.root / f"theme-{mode}"
                subprocess.run([
                    self.binary, "theme", "--theme-json", str(fixture), "--both",
                    "--default-mode", mode, "--render", f"{template}:{output}",
                ], check=True, env=self.environment, capture_output=True, text=True, timeout=30)
                rendered = output.read_text()
                self.assertNotIn("{{", rendered)
                self.assertIn(f"background = {expected}", rendered)
                self.assertIn(f"foreground = {expected}", rendered)
                self.assertEqual(sum(line.startswith("palette = ") for line in rendered.splitlines()), 16)

    def test_pinned_apply_hook_preserves_readonly_main_config_symlink(self):
        config = self.root / "config/ghostty/config"
        config.parent.mkdir(parents=True)
        target = self.root / "managed-config"
        contents = "theme = noctalia\nkeybind = shift+enter=text:\\x1b\\r\n"
        target.write_text(contents)
        target.chmod(0o444)
        config.symlink_to(target)
        hooks = self.root / "hooks"
        hooks.mkdir()
        shutil.copyfile(self.assets / "apply.sh", hooks / "apply.sh")
        marker = self.root / "reload-marker"
        # Never run the real reload script, which could signal a live terminal.
        (hooks / "reload.sh").write_text('printf reloaded > "$TEST_RELOAD_MARKER"\n')
        environment = dict(self.environment, TEST_RELOAD_MARKER=str(marker))
        subprocess.run([shutil.which("bash"), str(hooks / "apply.sh")],
                       check=True, env=environment, capture_output=True, text=True, timeout=10)
        self.assertTrue(config.is_symlink())
        self.assertEqual(config.resolve(), target)
        self.assertEqual(target.read_text(), contents)
        self.assertFalse(target.stat().st_mode & stat.S_IWUSR)
        self.assertEqual(marker.read_text(), "reloaded")


if __name__ == "__main__":
    unittest.main()
