"""Static manual-trial policy tests. Never authenticate, lock, scan or suspend."""

import json
import os
from pathlib import Path
import unittest


class NativeLockTrialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = json.loads(Path(os.environ["NATIVE_LOCK_POLICY"]).read_text())

    def test_secure_screen_defaults_for_the_manual_trial(self):
        screen = self.policy["screen"]
        self.assertTrue(screen["enabled"])
        self.assertFalse(screen["allow_empty_password"])
        self.assertEqual(screen["grace_period_seconds"], 0)
        self.assertFalse(screen["blurred_desktop"])
        self.assertEqual(screen["transition"], [])
        self.assertEqual(screen["monitors"], [])
        self.assertTrue(screen["fingerprint"])

    def test_native_manual_route_and_no_competing_logind_lock_listener(self):
        manual = self.policy["manual"]
        self.assertTrue(manual[0].endswith("/bin/noctalia"))
        self.assertEqual(manual[1:], ["msg", "session", "lock"])
        self.assertIsNone(self.policy["events"]["lock"])
        self.assertTrue(self.policy["fallback"])

    def test_automatic_and_pre_sleep_lock_routes_are_not_cut_over_yet(self):
        self.assertFalse(self.policy["screen"]["lock_before_suspend"])
        self.assertIn("/bin/swaylock -f", self.policy["events"]["before-sleep"])
        timeouts = {entry["timeout"]: entry for entry in self.policy["timeouts"]}
        self.assertEqual(set(timeouts), {300, 305, 310})
        self.assertIn("/bin/swaylock -f", timeouts[300]["command"])
        self.assertIn("power-off-monitors", timeouts[305]["command"])
        self.assertIn("power-on-monitors", timeouts[305]["resumeCommand"])
        self.assertEqual(timeouts[310]["command"], "safe-suspend")
        self.assertFalse(self.policy["idle"]["behavior"]["lock"]["enabled"])
        self.assertFalse(self.policy["idle"]["behavior"]["screen-off"]["enabled"])

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
