"""Real xrdb merging/preprocessing on a test-owned headless X server only."""

import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class XresourcesThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.state = self.root / "state"
        self.output = self.state / "noctalia/Xresources"
        self.output.parent.mkdir(parents=True)
        self.template = Path(os.environ["XRESOURCES_TEMPLATE"])
        self.target = self.root / "managed-resources"
        text = Path(os.environ["XRESOURCES_MAIN"]).read_text().replace(
            os.environ["MANAGED_STATE_HOME"], str(self.state))
        self.target.write_text(text)
        self.target.chmod(0o444)
        self.main = self.root / ".Xresources"
        self.main.symlink_to(self.target)
        self.hook = self.root / "apply.sh"
        body = Path(os.environ["XRESOURCES_HOOK"]).read_text()
        self.assertIn(os.environ["MANAGED_HOME"] + "/.Xresources", body)
        self.hook.write_text(body.replace(os.environ["MANAGED_HOME"], str(self.root)))
        self.environment = dict(os.environ)
        for key in ("DISPLAY", "XAUTHORITY", "NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME"):
            self.environment.pop(key, None)
        self.environment.update(HOME=str(self.root), XDG_STATE_HOME=str(self.state),
                                XDG_CONFIG_HOME=str(self.root / "config"),
                                XDG_CACHE_HOME=str(self.root / "cache"))
        self.server = None

    def stop_server(self):
        if self.server is not None:
            if self.server.poll() is None:
                self.server.terminate()
            self.server.communicate(timeout=5)

    def start_server(self):
        reader, writer = os.pipe()
        self.server = subprocess.Popen([
            os.environ["XVFB_CLI"], "-displayfd", str(writer), "-screen", "0", "800x600x24",
            "-nolisten", "tcp", "-noreset",
        ], pass_fds=(writer,), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.addCleanup(self.stop_server)
        os.close(writer)
        try:
            self.assertTrue(select.select([reader], [], [], 15)[0], "Test X server did not become ready")
            number = os.read(reader, 100).decode().strip()
            self.assertTrue(number.isdigit(), f"Invalid test display: {number!r}")
        finally:
            os.close(reader)
        self.environment["DISPLAY"] = ":" + number

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

    def apply(self):
        result = subprocess.run([shutil.which("bash"), str(self.hook)],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def query(self):
        result = subprocess.run([os.environ["XRDB_CLI"], "-query"],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return {key.strip(): value.strip() for key, value in
                (line.split(":", 1) for line in result.stdout.splitlines() if ":" in line)}

    def test_two_palettes_and_modes_reach_real_x_resource_database(self):
        self.start_server()
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                self.render(palette, mode)
                self.apply()
                actual = self.query()
                for key in ("*background", "*foreground", "*cursorColor", "*color0", "*color15", "Sxiv.background"):
                    self.assertEqual(actual[key], expected)
                self.assertEqual(actual["*.faceName"], "JetBrainsMono Nerd Font")
                self.assertEqual(actual["*.faceSize"], "11")
                self.assertEqual(actual["Xcursor.theme"], "Quintom_Snow")
                self.assertEqual(actual["Xcursor.size"], "24")

    def test_merge_keeps_unrelated_resources_and_is_idempotent(self):
        self.start_server()
        result = subprocess.run([os.environ["XRDB_CLI"], "-merge"], input="Unrelated.keep: yes\n",
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.apply()
        before = self.query()
        self.apply()
        self.assertEqual(self.query(), before)
        self.assertEqual(before["Unrelated.keep"], "yes")

    def test_no_display_skips_without_connecting_to_user_server(self):
        self.assertNotIn("DISPLAY", self.environment)
        self.apply()
        self.assertTrue(self.main.is_symlink())

    def test_real_merge_never_changes_managed_main_file(self):
        self.start_server()
        before = self.target.read_bytes()
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.apply()
        self.assertTrue(self.main.is_symlink())
        self.assertEqual(self.target.read_bytes(), before)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o444)
        self.assertTrue(before.decode().startswith(f'#include "{self.output}"'))

    def test_bootstrap_comments_work_with_real_preprocessor(self):
        self.start_server()
        migration.prepare(self.output, self.root / "backup", "! Awaiting native colors.")
        self.apply()
        self.assertEqual(self.query()["Xcursor.theme"], "Quintom_Snow")

    def test_protected_runtime_output_is_privatized_with_backup(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        before = self.output.read_bytes()
        self.output.chmod(0o444)
        backup = self.root / "backup"
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertFalse(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o644)


if __name__ == "__main__":
    unittest.main()
