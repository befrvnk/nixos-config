"""Execute native hook code with fake IPC and private runtime fixtures only."""

import fcntl
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


class WallpaperModeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()
        self.calls = self.root / "calls.jsonl"
        self.mode = self.root / "mode"
        self.mode.write_text("light")
        self.policy = json.loads(Path(os.environ["NOCTALIA_WALLPAPER_POLICY"]).read_text())
        self.fake = self.root / "noctalia"
        self.fake.write_text(f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import sys
import time
args = sys.argv[1:]
with Path(os.environ["FAKE_CALLS"]).open("a") as out:
    out.write(json.dumps(args) + "\\n")
if args == ["msg", "theme-mode-get"]:
    time.sleep(float(os.environ.get("FAKE_QUERY_DELAY", "0")))
    print(Path(os.environ["FAKE_MODE"]).read_text())
    sys.exit(int(os.environ.get("FAKE_QUERY_STATUS", "0")))
if args[:2] == ["msg", "wallpaper-set"] and len(args) == 3:
    entered = os.environ.get("FAKE_ENTERED")
    if entered:
        Path(entered).touch()
        while not Path(os.environ["FAKE_RELEASE"]).exists():
            time.sleep(0.01)
    time.sleep(float(os.environ.get("FAKE_SET_DELAY", "0")))
    print(os.environ.get("FAKE_REPLY", "ok"))
    sys.exit(int(os.environ.get("FAKE_SET_STATUS", "0")))
sys.exit("Unexpected IPC: " + repr(args))
''')
        self.fake.chmod(0o755)
        self.source = Path(self.policy["script"]).read_text()
        actual = os.environ["NOCTALIA_BIN"]
        self.assertIn(actual, self.source)
        self.source = self.source.replace(actual, str(self.fake))
        self.assertNotIn(actual, self.source)
        self.logger = self.root / "logger"
        self.logger.write_text(f"#!{sys.executable}\n" + '''
import os
from pathlib import Path
import sys
with Path(os.environ["FAKE_LOG"]).open("a") as out:
    out.write(" ".join(sys.argv[1:]) + "\\n")
''')
        self.logger.chmod(0o755)
        self.actual_logger = os.environ["ACTIVATION_UTIL_LINUX"] + "/bin/logger"
        self.assertIn(self.actual_logger, self.source)
        self.source = self.source.replace(self.actual_logger, str(self.logger))
        self.script = self.root / "hook.sh"
        self.script.write_text(self.source)
        self.bash = shutil.which("bash")
        self.environment = dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime),
                                FAKE_CALLS=str(self.calls), FAKE_MODE=str(self.mode),
                                FAKE_LOG=str(self.root / "journal"))
        for key in ("BASH_ENV", "ENV"):
            self.environment.pop(key, None)

    def run_hook(self, **environment):
        return subprocess.run([self.bash, str(self.script)],
                              env=dict(self.environment, **environment),
                              capture_output=True, text=True, timeout=10)

    def commands(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def test_resolved_light_and_dark_select_exact_existing_images(self):
        for mode in ("light", "dark"):
            with self.subTest(mode=mode):
                self.mode.write_text(mode)
                result = self.run_hook()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.commands()[-2:], [
                    ["msg", "theme-mode-get"],
                    ["msg", "wallpaper-set", self.policy["wallpapers"][mode]],
                ])
                self.assertTrue(Path(self.policy["wallpapers"][mode]).is_file())
                self.assertIn(f"Selected {mode} wallpaper via native hook",
                              (self.root / "journal").read_text())

    def test_stale_event_mode_is_ignored_in_favor_of_current_resolved_mode(self):
        result = self.run_hook(NOCTALIA_THEME_MODE="dark", NOCTALIA_THEME_MODE_CONFIGURED="auto")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands()[-1], ["msg", "wallpaper-set", self.policy["wallpapers"]["light"]])

    def test_invalid_unresolved_or_empty_mode_never_sets_wallpaper(self):
        for mode in ("auto", "invalid", "", "error: not ready"):
            with self.subTest(mode=mode):
                self.mode.write_text(mode)
                result = self.run_hook()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid resolved", result.stderr)
        self.assertTrue(all(args == ["msg", "theme-mode-get"] for args in self.commands()))

    def test_query_command_failure_does_not_select_a_default_image(self):
        result = self.run_hook(FAKE_QUERY_STATUS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [["msg", "theme-mode-get"]])

    def test_error_empty_or_unexpected_set_reply_fails_even_with_zero_status(self):
        for reply in ("error: unavailable", "", "unexpected"):
            with self.subTest(reply=reply):
                result = self.run_hook(FAKE_REPLY=reply)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Native wallpaper selection failed", result.stderr)
                self.assertIn("Native wallpaper selection failed", (self.root / "journal").read_text())

    def test_set_command_failure_is_not_hidden(self):
        result = self.run_hook(FAKE_SET_STATUS="1")
        self.assertNotEqual(result.returncode, 0)

    def test_missing_or_empty_runtime_never_creates_it_or_calls_ipc(self):
        missing = self.root / "missing-runtime"
        for runtime in ("", str(missing)):
            with self.subTest(runtime=runtime):
                result = self.run_hook(XDG_RUNTIME_DIR=runtime)
                self.assertNotEqual(result.returncode, 0)
        self.assertFalse(missing.exists())
        self.assertEqual(self.commands(), [])

    def test_same_mode_startup_reasserts_the_pair_without_applied_generation_cache(self):
        for _ in range(2):
            result = self.run_hook()
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.commands()), 4)
        self.assertEqual(sorted(p.name for p in self.runtime.iterdir()),
                         ["noctalia-wallpaper-mode.lock"])

    def test_both_native_hooks_share_the_same_script_and_preserve_bridge_hook(self):
        script = self.policy["script"]
        self.assertIn(script, self.policy["hooks"]["started"])
        self.assertEqual(self.policy["hooks"]["theme_mode_changed"][0], script)
        self.assertEqual(len(self.policy["hooks"]["theme_mode_changed"]), 2)
        self.assertNotEqual(self.policy["hooks"]["theme_mode_changed"][1], script)
        self.assertFalse(any("noctalia-wallpaper" in unit for unit in self.policy["userUnits"]))

    def test_bridge_no_longer_has_wallpaper_paths(self):
        self.assertFalse(any(entry.startswith("NOCTALIA_WALLPAPER_")
                             for entry in self.policy["bridgeEnvironment"]))
        bridge = Path(__file__).with_name("theme_bridge.py").read_text()
        self.assertNotIn("wallpaper-set", bridge)
        self.assertNotIn("NOCTALIA_WALLPAPER_", bridge)

    def test_query_timeout_is_bounded(self):
        self.script.write_text(self.source.replace("timeout 10s", "timeout 0.05s"))
        result = self.run_hook(FAKE_QUERY_DELAY="2")
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn("Wallpaper hook failed (exit 124)", (self.root / "journal").read_text())
        self.assertFalse(any(args[:2] == ["msg", "wallpaper-set"] for args in self.commands()))

    def test_set_timeout_is_bounded(self):
        self.script.write_text(self.source.replace("timeout 30s", "timeout 0.05s"))
        result = self.run_hook(FAKE_SET_DELAY="2")
        self.assertEqual(result.returncode, 124, result.stderr)

    def test_overlapping_hooks_query_under_lock_and_finish_with_current_mode(self):
        entered, release = self.root / "entered", self.root / "release"
        processes = []
        try:
            first = subprocess.Popen([self.bash, str(self.script)],
                env=dict(self.environment, FAKE_ENTERED=str(entered), FAKE_RELEASE=str(release)),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            processes.append(first)
            deadline = time.monotonic() + 5
            while not entered.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(entered.exists(), "First fixture did not reach native setter")
            with (self.runtime / "noctalia-wallpaper-mode.lock").open("a") as lock:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.mode.write_text("dark")
            second = subprocess.Popen([self.bash, str(self.script)],
                env=dict(self.environment, NOCTALIA_THEME_MODE="light"),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            processes.append(second)
            release.touch()
            for process in processes:
                _, stderr = process.communicate(timeout=10)
                self.assertEqual(process.returncode, 0, stderr)
            self.assertEqual(self.commands(), [
                ["msg", "theme-mode-get"], ["msg", "wallpaper-set", self.policy["wallpapers"]["light"]],
                ["msg", "theme-mode-get"], ["msg", "wallpaper-set", self.policy["wallpapers"]["dark"]],
            ])
        finally:
            release.touch()
            for process in processes:
                if process.poll() is None:
                    process.kill()  # Private fixture child only, never a desktop process.
                    process.communicate(timeout=10)

    def test_template_quotes_paths_with_spaces_and_apostrophes(self):
        source = Path(__file__).with_name("wallpaper-mode.sh").read_text()
        light = str(self.root / "light mountain's image.jpg")
        for key, value in {
            "@coreutils@": os.environ["ACTIVATION_COREUTILS"],
            "@util_linux@": os.environ["ACTIVATION_UTIL_LINUX"],
            "@noctalia@": shlex.quote(str(self.fake)),
            "@light@": shlex.quote(light), "@dark@": shlex.quote("dark.jpg"),
        }.items():
            source = source.replace(key, value)
        self.script.write_text(source.replace(self.actual_logger, str(self.logger)))
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands()[-1], ["msg", "wallpaper-set", light])


if __name__ == "__main__":
    unittest.main()
