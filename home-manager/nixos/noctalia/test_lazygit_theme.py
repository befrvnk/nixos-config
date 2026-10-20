"""Native layered config and terminal colors, isolated from user repositories."""

import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unittest

import prepare_theme_output as migration


class LazygitThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "config/lazygit/themes/noctalia.yml"
        self.output.parent.mkdir(parents=True)
        self.template = Path(os.environ["COMMUNITY_TEMPLATE_SOURCE"]) / "lazygit/lazygit.yml"
        self.environment = dict(os.environ)
        self.environment.pop("LG_CONFIG_FILE", None)
        self.environment.update(
            HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_DATA_HOME=str(self.root / "data"), XDG_STATE_HOME=str(self.root / "state"),
            XDG_CACHE_HOME=str(self.root / "cache"), GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL="/dev/null", TERM="xterm-256color", COLORTERM="truecolor",
        )
        self.base_target = self.root / "managed-base.yml"
        # A nondefault quit key proves unrelated base config survives the overlay.
        self.base_target.write_text('''gui:
  theme:
    activeBorderColor: ["#010101"]
keybinding:
  universal:
    quit: x
disableStartupPopups: true
update:
  method: never
git:
  autoFetch: false
''')
        self.base_target.chmod(0o444)
        self.base = self.output.parent.parent / "config.yml"
        self.base.symlink_to(self.base_target)
        self.repo = self.root / "repo"
        subprocess.run(["git", "init", "-q", "-b", "test", str(self.repo)],
                       check=True, env=self.environment, capture_output=True)
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=Theme Test",
                        "-c", "user.email=theme@example.invalid", "commit", "--allow-empty",
                        "-qm", "test fixture"], check=True, env=self.environment, capture_output=True)

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

    def run_tui(self, expected, explicit=False):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        files = f"{self.base},{self.output}"
        environment = dict(self.environment, LG_CONFIG_FILE=files)
        args = [os.environ["LAZYGIT_CLI"]]
        if explicit:
            environment["LG_CONFIG_FILE"] = str(self.root / "must-not-load.yml")
            args.extend(["--use-config-file", files])
        process = None
        captured = bytearray()
        rgb = tuple(int(expected[i:i+2], 16) for i in (1, 3, 5))
        marker = (";2;%d;%d;%d" % rgb).encode()
        try:
            process = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                                       cwd=self.repo, env=environment, preexec_fn=controlling_terminal)
            os.close(slave)
            slave = None
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline and marker not in captured:
                if not select.select([master], [], [], 0.1)[0]:
                    if process.poll() is not None:
                        break
                    continue
                try:
                    captured.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
            self.assertIn(marker, captured, bytes(captured[-2500:]))
            os.write(master, b"x")
            self.assertEqual(process.wait(timeout=8), 0, bytes(captured[-2500:]))
        finally:
            if process is not None and process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            os.close(master)
            if slave is not None:
                os.close(slave)

    def test_stock_theme_renders_two_palettes_in_both_modes(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                self.render(palette, mode)
                self.assertIn(f'"{expected}"', self.output.read_text())
                self.assertTrue(self.output.read_text().startswith("gui:\n  theme:\n"))

    def test_real_lazygit_merges_base_and_uses_generated_truecolor(self):
        before = self.base_target.read_bytes()
        for mode, expected in (("dark", "#123456"), ("light", "#d0e0f0")):
            with self.subTest(mode=mode):
                self.render({"dark": "#123456", "light": "#d0e0f0"}, mode)
                self.run_tui(expected)
        self.assertEqual(self.base_target.read_bytes(), before)
        self.assertTrue(self.base.is_symlink())

    def test_explicit_config_flag_overrides_custom_environment(self):
        self.render({"dark": "#653412", "light": "#f0e0d0"}, "dark")
        self.run_tui("#653412", explicit=True)

    def test_wrapper_uses_native_default_list_without_settings_hook(self):
        wrapper = Path(os.environ["LAZYGIT_WRAPPER"]).read_text()
        root = os.environ["MANAGED_CONFIG_HOME"] + "/lazygit"
        self.assertIn(f"{root}/config.yml,{root}/themes/noctalia.yml", wrapper)
        self.assertIn("LG_CONFIG_FILE", wrapper)
        registration = json.loads(Path(os.environ["LAZYGIT_REGISTRATION"]).read_text())
        self.assertEqual(set(registration), {"input_path", "output_path"})
        base = Path(os.environ["LAZYGIT_BASE"]).read_text()
        self.assertIn("gui:", base)
        self.assertNotIn("activeBorderColor", base)

    def test_rendering_never_changes_the_managed_base(self):
        before = self.base_target.read_bytes()
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.render({"dark": "#653412", "light": "#f0e0d0"}, "light")
        self.assertEqual(self.base_target.read_bytes(), before)
        self.assertEqual(self.base_target.stat().st_mode & 0o777, 0o444)

    def test_bootstrap_and_legacy_output_are_safe(self):
        backup = self.root / "backup.yml"
        migration.prepare(self.output, backup, "{}")
        self.assertEqual(self.output.read_text(), "{}")
        self.output.chmod(0o444)
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_text(), "{}")
        self.assertFalse(migration.prepare(self.output, backup, "unused"))


if __name__ == "__main__":
    unittest.main()
