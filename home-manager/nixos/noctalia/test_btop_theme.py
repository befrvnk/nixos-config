"""Pinned btop theme/hook; real reload is tested only on our isolated child."""

import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time
import json
import unittest

import prepare_theme_output as migration


class BtopThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config_dir = self.root / "config/btop"
        self.output = self.config_dir / "themes/noctalia.theme"
        self.output.parent.mkdir(parents=True)
        self.target = self.root / "managed-btop.conf"
        self.target.write_bytes(Path(os.environ["BTOP_CONFIG"]).read_bytes())
        self.target.chmod(0o444)
        self.config = self.config_dir / "btop.conf"
        self.config.symlink_to(self.target)
        self.assets = Path(os.environ["NOCTALIA_SOURCE"]) / "assets/templates/btop"
        self.environment = dict(os.environ)
        self.environment.update(HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / "config"),
                                XDG_STATE_HOME=str(self.root / "state"),
                                XDG_DATA_HOME=str(self.root / "data"), XDG_CACHE_HOME=str(self.root / "cache"),
                                TERM="xterm-256color", COLORTERM="truecolor")
        tools = self.root / "bin"
        tools.mkdir()
        self.calls = self.root / "signals"
        header = f"#!{shutil.which('bash')}\n"
        (tools / "pgrep").write_text(header + 'exit "${MOCK_BTOP_RUNNING:-0}"\n')
        (tools / "pkill").write_text(header + 'printf "%s\\n" "$*" >> "$BTOP_TEST_SIGNALS"\n')
        for tool in tools.iterdir():
            tool.chmod(0o755)
        self.environment.update(PATH=f"{tools}:{os.environ['PATH']}", BTOP_TEST_SIGNALS=str(self.calls))

    def render(self, palette, mode):
        template = self.assets / "btop.theme"
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

    def apply(self):
        result = subprocess.run([shutil.which("bash"), str(self.assets / "apply.sh")],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_two_palettes_and_modes_render_native_theme_fields(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                self.render(palette, mode)
                fields = dict(re.findall(r'^theme\[([^]]+)\]="(#[0-9a-fA-F]{6})"$',
                                         self.output.read_text(), re.MULTILINE))
                self.assertGreater(len(fields), 30)
                for key in ("main_bg", "main_fg", "title", "cpu_box", "cpu_start", "mem_box"):
                    self.assertEqual(fields[key], expected)

    def test_stock_hook_preserves_managed_selector_and_only_requests_native_reload(self):
        before = self.target.read_bytes()
        self.apply()
        self.assertEqual(self.calls.read_text(), "-SIGUSR2 -x btop\n")
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(self.target.read_bytes(), before)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o444)

    def test_stock_hook_does_not_signal_when_no_btop_is_running(self):
        self.environment["MOCK_BTOP_RUNNING"] = "1"
        self.apply()
        self.assertFalse(self.calls.exists())

    def test_real_btop_reads_and_reloads_palette_on_its_own_sigusr2(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        process = None
        captured = bytearray()
        def wait_for_rgb(color):
            marker = (";2;%d;%d;%d" % tuple(int(color[i:i+2], 16) for i in (1, 3, 5))).encode()
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
        before = self.target.read_bytes()
        try:
            process = subprocess.Popen([
                os.environ["BTOP_CLI"], "--config", str(self.config), "--themes-dir", str(self.output.parent),
                "--force-utf", "--no-tty",
            ], stdin=slave, stdout=slave, stderr=slave, cwd=self.root,
                env=self.environment, preexec_fn=controlling_terminal)
            os.close(slave)
            slave = None
            wait_for_rgb("#123456")
            captured.clear()
            self.render({"dark": "#653412", "light": "#f0e0d0"}, "light")
            # Never use process-wide pkill here: only our test-owned child.
            os.kill(process.pid, signal.SIGUSR2)
            wait_for_rgb("#f0e0d0")
            os.write(master, b"q")
            self.assertEqual(process.wait(timeout=8), 0)
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
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(self.target.read_bytes(), before)

    def test_update_rate_keys_and_declarative_selector_are_preserved(self):
        text = self.target.read_text()
        self.assertIn('color_theme = "noctalia"', text)
        self.assertIn("update_ms = 1000", text)
        self.assertIn("vim_keys = False", text)
        self.assertNotIn('color_theme = "stylix"', text)

    def test_bootstrap_and_protected_output_leave_managed_config_untouched(self):
        before = self.target.read_bytes()
        backup = self.root / "original.theme"
        migration.prepare(self.output, backup, "# Awaiting native btop colors.")
        self.assertTrue(self.output.read_text().startswith("#"))
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        contents = self.output.read_bytes()
        self.output.chmod(0o444)
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_bytes(), contents)
        self.assertFalse(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(self.target.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
