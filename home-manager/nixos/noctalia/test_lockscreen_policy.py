"""Native lock/idle policy probes. Never authenticate, lock, scan or suspend."""

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


class NativeLockPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = json.loads(Path(os.environ["NATIVE_LOCK_POLICY"]).read_text())
        cls.suspend_helper = cls.policy["manualSuspend"][0]

    def test_secure_screen_defaults(self):
        screen = self.policy["screen"]
        self.assertTrue(screen["enabled"])
        self.assertFalse(screen["allow_empty_password"])
        self.assertEqual(screen["grace_period_seconds"], 0)
        self.assertFalse(screen["blurred_desktop"])
        self.assertEqual(screen["transition"], [])
        self.assertEqual(screen["monitors"], [])
        self.assertTrue(screen["fingerprint"])
        self.assertTrue(screen["lock_before_suspend"])

    def test_native_manual_route_and_retained_rollback(self):
        manual = self.policy["manual"]
        self.assertTrue(manual[0].endswith("/bin/noctalia"))
        self.assertEqual(manual[1:], ["msg", "session", "lock"])
        self.assertTrue(self.policy["fallback"])

    def test_native_idle_actions_preserve_elapsed_timings_without_extra_fade(self):
        idle = self.policy["idle"]
        self.assertEqual(idle["behavior_order"], ["lock", "screen-off", "suspend"])
        self.assertEqual(idle["pre_action_fade_seconds"], 0)
        expected = {
            "lock": (300, "lock"),
            "screen-off": (305, "screen_off"),
            "suspend": (310, "lock_and_suspend"),
        }
        self.assertEqual(set(idle["behavior"]), set(expected))
        for name, (timeout, action) in expected.items():
            self.assertEqual(idle["behavior"][name], {
                "action": action, "enabled": True,
                "locked_timeout": 0, "timeout": timeout,
            })

    def test_no_competing_swayidle_scheduler_or_dummy_hooks(self):
        self.assertFalse(self.policy["swayidleEnabled"])
        self.assertNotIn("swayidle", self.policy["userUnits"])
        self.assertIn("noctalia", self.policy["userUnits"])

    def test_session_panel_and_power_command_cannot_request_unlocked_sleep(self):
        session = self.policy["session"]
        self.assertEqual(session["power"]["suspend"], f"{self.suspend_helper} --require-lock")
        actions = [entry["action"] for entry in session["actions"]]
        self.assertEqual(actions, ["lock", "logout", "lock_and_suspend", "reboot", "shutdown"])
        self.assertNotIn("suspend", actions)

    def test_suspend_backend_resolves_even_with_an_empty_path(self):
        # Resolve the executable only: never execute the helper or systemctl.
        shell = shutil.which("sh")
        self.assertIsNotNone(shell)
        self.assertTrue(self.suspend_helper.startswith("/nix/store/"))
        self.assertTrue(os.access(self.suspend_helper, os.X_OK))
        self.assertEqual(self.policy["manualSuspend"], [self.suspend_helper])
        parts = shlex.split(self.policy["session"]["power"]["suspend"])
        self.assertEqual(parts, [self.suspend_helper, "--require-lock"])
        result = subprocess.run(
            [shell, "-c", 'command -v "$1"', "resolution-probe", parts[0]],
            env={"PATH": ""}, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.suspend_helper)
        original = subprocess.run(
            [shell, "-c", "command -v safe-suspend"], env={"PATH": ""},
            capture_output=True, text=True, timeout=10,
        )
        self.assertNotEqual(original.returncode, 0)

    def test_configured_binary_accepts_native_idle_and_power_config(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [os.environ["NOCTALIA_BIN"], "config", "validate", self.policy["configSource"]],
                env=dict(os.environ, HOME=directory, XDG_CONFIG_HOME=directory,
                         XDG_STATE_HOME=directory),
                capture_output=True, text=True, timeout=30,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_password_stack_requires_unix_and_does_not_share_fingerprint_sensor(self):
        lines = [line.split() for line in self.policy["passwordPam"].splitlines() if line.strip()]
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0][:2], ["auth", "required"])
        self.assertEqual(lines[1][:2], ["account", "required"])
        self.assertTrue(all(len(line) == 3 and line[2].endswith("/pam_unix.so") for line in lines))
        self.assertNotIn("fprint", self.policy["passwordPam"])
        self.assertNotIn("nullok", self.policy["passwordPam"])


if __name__ == "__main__":
    unittest.main()
