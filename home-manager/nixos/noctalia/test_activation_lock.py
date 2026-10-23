"""Run only rendered hook fragments against private fixtures, never HM activation."""

from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import socket
import subprocess
import tempfile
import unittest


class ActivationLockTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.runtime = self.root / "runtime"
        self.lock = self.root / "state/noctalia/theme-activation.lock"
        self.calls = self.root / "systemctl-calls"
        self.bash = shutil.which("bash")
        self.assertIsNotNone(self.bash)
        self.core = self.root / "coreutils"
        self.systemd = self.root / "systemd"
        (self.core / "bin").mkdir(parents=True)
        (self.systemd / "bin").mkdir(parents=True)
        coreutils = os.environ["ACTIVATION_COREUTILS"]
        (self.core / "bin/mkdir").symlink_to(Path(coreutils) / "bin/mkdir")
        self.fake_id = self.core / "bin/id"
        self.fake_id.write_text(f"#!{self.bash}\nprintf '%s\\n' 2147483647\n")
        self.fake_id.chmod(0o755)
        self.systemctl = self.systemd / "bin/systemctl"
        self.systemctl.write_text(
            f"#!{self.bash}\nprintf '%s\\n' \"$*\" >> \"$FAKE_CALLS\"\n"
        )
        self.systemctl.chmod(0o755)
        self.request_calls = self.root / "request-calls"
        self.request = self.root / "request"
        self.request.write_text(
            f"#!{self.bash}\nprintf '%s\\n' \"$*\" >> \"$FAKE_REQUEST_CALLS\"\n"
        )
        self.request.chmod(0o755)
        self.hook = Path(__file__).with_name("activation-lock.sh").read_text()
        for key, value in {
            "@activation_lock@": shlex.quote(str(self.lock)),
            "@coreutils@": str(self.core),
            "@systemd@": str(self.systemd),
            "@util_linux@": os.environ["ACTIVATION_UTIL_LINUX"],
        }.items():
            self.hook = self.hook.replace(key, value)
        self.environment = dict(os.environ)
        for key in ("XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "DARKMAN_RUNNING",
                    "NOCTALIA_THEME_BRIDGE_ACTIVE", "BASH_ENV", "ENV"):
            self.environment.pop(key, None)
        self.environment.update(HOME=str(self.root), DRY_RUN_CMD="", FAKE_CALLS=str(self.calls),
                                FAKE_REQUEST_CALLS=str(self.request_calls))

    @contextmanager
    def holding_hook(self, **environment):
        script = self.hook + '\nprintf "READY:%s\\n" "${XDG_RUNTIME_DIR:-unset}"\nread -r release\n'
        process = subprocess.Popen(
            [self.bash, "--noprofile", "--norc", "-eu", "-c", script],
            env=dict(self.environment, **environment), stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            ready, _, _ = select.select([process.stdout], [], [], 10)
            self.assertTrue(ready, "Fixture hook did not become ready")
            line = process.stdout.readline().strip()
            self.assertTrue(line.startswith("READY:"), line)
            yield line
        finally:
            try:
                _, stderr = process.communicate(input="release\n", timeout=10)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                process.kill()
                _, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stderr)

    def assert_locked(self, path):
        self.assertTrue(path.is_file(), path)
        with path.open("a") as lock:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_absent_runtime_directory_is_not_created(self):
        with self.holding_hook(XDG_RUNTIME_DIR=str(self.runtime)):
            self.assert_locked(self.lock)
            self.assertFalse(self.runtime.exists())
            self.assertFalse(self.calls.exists())

    def test_unset_or_empty_runtime_env_still_holds_the_state_lock(self):
        for environment in ({}, {"XDG_RUNTIME_DIR": ""}):
            with self.subTest(environment=environment), self.holding_hook(**environment):
                self.assert_locked(self.lock)
                self.assertFalse(self.calls.exists())

    def test_session_without_bus_exports_runtime_and_keeps_legacy_serialization(self):
        self.runtime.mkdir()
        with self.holding_hook(XDG_RUNTIME_DIR=str(self.runtime)) as line:
            self.assertEqual(line, f"READY:{self.runtime}")
            self.assert_locked(self.lock)
            self.assert_locked(self.runtime / "noctalia-theme/activation.lock")
            self.assertFalse(self.calls.exists())

    def test_dry_run_and_bridge_child_do_not_take_or_create_locks(self):
        for environment in ({"DRY_RUN_CMD": "echo"}, {"NOCTALIA_THEME_BRIDGE_ACTIVE": "1"}):
            with self.subTest(environment=environment), self.holding_hook(**environment):
                self.assertFalse(self.lock.exists())
                self.assertFalse(self.runtime.exists())
                self.assertFalse(self.calls.exists())

    def overview_hook(self):
        source = Path(os.environ["NOCTALIA_OVERVIEW_ENSURE"]).read_text()
        actual = os.environ["ACTIVATION_SYSTEMCTL"]
        self.assertIn(actual, source)
        source = source.replace(actual, shlex.quote(str(self.systemctl)))
        self.assertNotIn(actual, source)
        return source

    def test_overview_hook_defers_without_a_session_bus(self):
        for runtime in ("", str(self.runtime)):
            result = subprocess.run(
                [self.bash, "-eu", "-c", self.overview_hook()],
                env=dict(self.environment, XDG_RUNTIME_DIR=runtime),
                capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(self.calls.exists())

    def test_overview_hook_still_requests_an_idempotent_start_in_session(self):
        self.runtime.mkdir()
        with socket.socket(socket.AF_UNIX) as bus:
            bus.bind(str(self.runtime / "bus"))
            result = subprocess.run(
                [self.bash, "-eu", "-c", self.overview_hook()],
                env=dict(self.environment, XDG_RUNTIME_DIR=str(self.runtime)),
                capture_output=True, text=True, timeout=10,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().strip(),
                         "--user --no-block start noctalia-overview.service")

    def request_hook(self):
        source = Path(os.environ["NOCTALIA_THEME_REQUEST"]).read_text()
        replacements = {
            os.environ["ACTIVATION_SYSTEMCTL"]: str(self.systemctl),
            os.environ["ACTIVATION_THEME_REQUEST"]: str(self.request),
        }
        for actual, fake in replacements.items():
            self.assertIn(actual, source)
            source = source.replace(actual, shlex.quote(fake))
            self.assertNotIn(actual, source)
        return source

    def test_request_hook_before_login_does_not_start_user_units(self):
        result = subprocess.run(
            [self.bash, "-eu", "-c", self.request_hook()],
            env=dict(self.environment, XDG_RUNTIME_DIR=""),
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.request_calls.read_text().strip(), "--force --refresh")
        self.assertFalse(self.calls.exists())

    def test_request_hook_restores_the_path_watcher_asynchronously_in_session(self):
        self.runtime.mkdir()
        with socket.socket(socket.AF_UNIX) as bus:
            bus.bind(str(self.runtime / "bus"))
            result = subprocess.run(
                [self.bash, "-eu", "-c", self.request_hook()],
                env=dict(self.environment, XDG_RUNTIME_DIR=str(self.runtime)),
                capture_output=True, text=True, timeout=10,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.request_calls.read_text().strip(), "--force --refresh")
        self.assertEqual(self.calls.read_text().strip(),
                         "--user --no-block start noctalia-theme.path")

    def test_request_hook_skips_dry_runs_and_bridge_children(self):
        for environment in ({"DRY_RUN_CMD": "echo"}, {"NOCTALIA_THEME_BRIDGE_ACTIVE": "1"}):
            with self.subTest(environment=environment):
                result = subprocess.run(
                    [self.bash, "-eu", "-c", self.request_hook()],
                    env=dict(self.environment, **environment),
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.request_calls.exists())
                self.assertFalse(self.calls.exists())

    def test_worker_startup_readiness_cannot_wait_for_hm_completion(self):
        service = json.loads(Path(os.environ["NOCTALIA_THEME_SERVICE"]).read_text())
        self.assertEqual(service["Service"]["Type"], "exec")
        self.assertEqual(service["Service"]["Restart"], "on-failure")
        self.assertNotIn("TimeoutStartSec", service["Service"])


if __name__ == "__main__":
    unittest.main()
