"""Upstream Bash colors through the real fzf wrapper, including Nushell and PTYs."""

import errno
import fcntl
import json
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
import unittest

import prepare_theme_output as migration


class FzfThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "config/fzf/themes/noctalia.sh"
        self.output.parent.mkdir(parents=True)
        self.template = Path(os.environ["COMMUNITY_TEMPLATE_SOURCE"]) / "fzf/fzf.sh"
        self.environment = dict(os.environ)
        for key in list(self.environment):
            if key.startswith("FZF_") or key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME"):
                self.environment.pop(key, None)
        self.environment.update(
            HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_DATA_HOME=str(self.root / "data"), XDG_STATE_HOME=str(self.root / "state"),
            XDG_CACHE_HOME=str(self.root / "cache"), TERM="xterm-256color", COLORTERM="truecolor",
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

    def filter(self, args, text="left:match\nmatch:nope\n"):
        return subprocess.run([os.environ["FZF_WRAPPER"], *args], input=text,
                              env=self.environment, capture_output=True, text=True, timeout=10)

    def test_stock_snippet_renders_two_palettes_and_preserves_existing_options(self):
        base = "--exact --delimiter=: --nth=2"
        self.environment["FZF_DEFAULT_OPTS"] = base
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                self.render(palette, mode)
                result = subprocess.run([
                    shutil.which("bash"), "-c", 'source "$1"; printf "%s" "$FZF_DEFAULT_OPTS"',
                    "test", str(self.output),
                ], env=self.environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(result.stdout.startswith(base + "\n"))
                colors = [line for line in result.stdout.splitlines() if line.startswith("--color=")]
                self.assertEqual(len(colors), 15)
                self.assertTrue(all(line.endswith(expected) for line in colors))

    def test_real_wrapper_honors_options_and_explicit_cli_overrides(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.environment["FZF_DEFAULT_OPTS"] = "--exact --delimiter=: --nth=2"
        result = self.filter(["--filter", "match"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "left:match\n")
        result = self.filter(["--filter", "match", "--nth=1"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "match:nope\n")

    def test_existing_default_options_file_still_applies(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "light")
        options = self.root / "options"
        options.write_text("--exact --delimiter=: --nth=2\n")
        self.environment.update(FZF_DEFAULT_OPTS_FILE=str(options), FZF_DEFAULT_OPTS="--no-sort")
        result = self.filter(["--filter", "match"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "left:match\n")
        self.assertEqual(options.read_text(), "--exact --delimiter=: --nth=2\n")

    def test_nushell_repeated_calls_do_not_mutate_or_accumulate_parent_options(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        environment = dict(self.environment, NOCTALIA_TEST_FZF=os.environ["FZF_WRAPPER"])
        code = '''
$env.FZF_DEFAULT_OPTS = '--exact'
let first = (['alpha' 'beta'] | str join (char nl) | run-external $env.NOCTALIA_TEST_FZF '--filter' beta)
let second = (['alpha' 'beta'] | str join (char nl) | run-external $env.NOCTALIA_TEST_FZF '--filter' alpha)
{first: ($first | str trim), second: ($second | str trim), opts: $env.FZF_DEFAULT_OPTS} | to json --raw
'''
        result = subprocess.run([os.environ["NUSHELL_CLI"], "--no-config-file", "-c", code],
                                env=environment, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"first": "beta", "second": "alpha", "opts": "--exact"})

    def run_picker(self, expected):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(2, termios.TIOCSCTTY, 0)
        process = None
        captured = bytearray()
        rgb = tuple(int(expected[i:i+2], 16) for i in (1, 3, 5))
        marker = (";2;%d;%d;%d" % rgb).encode()
        try:
            process = subprocess.Popen([os.environ["FZF_WRAPPER"], "--no-sort"],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=slave,
                                       cwd=self.root, env=self.environment, preexec_fn=controlling_terminal)
            os.close(slave)
            slave = None
            process.stdin.write(b"alpha\nbeta\n")
            process.stdin.close()
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
            os.write(master, b"\r")
            self.assertEqual(process.wait(timeout=8), 0, bytes(captured[-2500:]))
            self.assertEqual(process.stdout.read(), b"alpha\n")
        finally:
            if process is not None and process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            if process is not None:
                process.stdout.close()
            os.close(master)
            if slave is not None:
                os.close(slave)

    def test_new_pickers_use_latest_palette_with_real_truecolor_output(self):
        for mode, expected in (("dark", "#123456"), ("light", "#d0e0f0")):
            self.render({"dark": "#123456", "light": "#d0e0f0"}, mode)
            self.run_picker(expected)

    def test_missing_bootstrap_and_protected_snippets_are_safe(self):
        self.assertEqual(self.filter(["--filter", "match"], "match\n").returncode, 0)
        backup = self.root / "backup.sh"
        migration.prepare(self.output, backup, "# Awaiting native colors.")
        self.assertEqual(self.filter(["--filter", "match"], "match\n").returncode, 0)
        self.output.chmod(0o444)
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_text(), "# Awaiting native colors.")
        self.assertFalse(migration.prepare(self.output, backup, "unused"))

    def test_registration_has_only_the_upstream_bash_input_and_no_hook(self):
        registration = json.loads(Path(os.environ["FZF_REGISTRATION"]).read_text())
        self.assertEqual(set(registration), {"input_path", "output_path"})
        self.assertTrue(registration["input_path"].endswith("/fzf/fzf.sh"))
        self.assertEqual(registration["output_path"], "$XDG_CONFIG_HOME/fzf/themes/noctalia.sh")


if __name__ == "__main__":
    unittest.main()
