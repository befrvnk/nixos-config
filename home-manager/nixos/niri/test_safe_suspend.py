"""Exercise safe-suspend with fake busctl/notify-send/systemctl, never real sleep."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


STUB = r'''#!{python}
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ["CALLS"], "a") as output:
    output.write(json.dumps([name, *sys.argv[1:]]) + "\n")
if name == "busctl":
    print(os.environ["INHIBITORS"])
    sys.exit(int(os.environ.get("BUSCTL_EXIT", "0")))
if name == "systemctl":
    sys.exit(int(os.environ.get("SUSPEND_EXIT", "0")))
sys.exit(int(os.environ.get("NOTIFY_EXIT", "0")))
'''


def row(what, who="Example Blocker", mode="block"):
    return [what, who, "Reason with spaces", mode, 1000, 12345]


class SafeSuspendTests(unittest.TestCase):
    def run_helper(self, rows=(), *, raw=None, **variables):
        bash = shutil.which("bash")
        jq = shutil.which("jq")
        self.assertIsNotNone(bash)
        self.assertIsNotNone(jq)
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            tools = directory / "bin"
            tools.mkdir()
            for name in ("busctl", "notify-send", "systemctl"):
                command = tools / name
                command.write_text(STUB.format(python=sys.executable))
                command.chmod(0o755)
            calls = directory / "calls.jsonl"
            # Only jq is real on this PATH. It contains no real systemctl/busctl,
            # so an accidental missing test stub cannot call the host's services.
            (tools / "jq").symlink_to(jq)
            environment = dict(os.environ, **variables)
            environment.update(
                PATH=str(tools),
                CALLS=str(calls),
                INHIBITORS=raw if raw is not None else json.dumps({"type": "a(ssssuu)", "data": [list(rows)]}),
            )
            result = subprocess.run(
                [bash, str(Path(__file__).with_name("safe-suspend.sh"))],
                env=environment, capture_output=True, text=True, timeout=10,
            )
            recorded = [json.loads(line) for line in calls.read_text().splitlines()]
            return result, recorded

    def assert_suspended(self, result, calls):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c for c in calls if c[0] == "systemctl"], [["systemctl", "suspend"]])
        self.assertFalse(any(c[0] == "notify-send" for c in calls))

    def assert_blocked(self, result, calls):
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == "systemctl" for c in calls))
        self.assertTrue(any(c[0] == "notify-send" for c in calls))

    def test_no_inhibitors(self):
        self.assert_suspended(*self.run_helper())

    def test_idle_and_lid_only_are_not_sleep_blocks(self):
        self.assert_suspended(*self.run_helper([
            row("idle", "noctalia"), row("handle-lid-switch", "Noctalia Lid Guard"),
        ]))

    def test_sleep_delay_does_not_block_lock_before_sleep(self):
        self.assert_suspended(*self.run_helper([row("sleep", "swayidle", "delay")]))

    def test_combined_sleep_block(self):
        result, calls = self.run_helper([row("idle:sleep", "Audio Playback")])
        self.assert_blocked(result, calls)
        self.assertIn("Audio Playback", json.dumps(calls))

    def test_names_with_spaces_and_multiple_blockers(self):
        result, calls = self.run_helper([
            row("sleep", "A Blocker With Spaces"), row("sleep", "Another Blocker"),
        ])
        self.assert_blocked(result, calls)
        self.assertIn("A Blocker With Spaces, Another Blocker", json.dumps(calls))

    def test_exact_sleep_token(self):
        self.assert_suspended(*self.run_helper([row("handle-suspend-key:idle")]))

    def test_weak_block_is_left_to_logind(self):
        self.assert_suspended(*self.run_helper([row("sleep", mode="block-weak")]))

    def test_bus_failure_fails_closed(self):
        self.assert_blocked(*self.run_helper(BUSCTL_EXIT="1"))

    def test_invalid_json_or_shape_fails_closed(self):
        for response in ("not json", "null", "{}", '{"type":"s","data":["sleep"]}',
                         '{"type":"a(ssssuu)","data":[[["sleep"]]]}'):
            with self.subTest(response=response):
                self.assert_blocked(*self.run_helper(raw=response))

    def test_notification_failure_does_not_request_sleep(self):
        self.assert_blocked(*self.run_helper([row("sleep")], NOTIFY_EXIT="1"))

    def test_suspend_error_propagates(self):
        result, calls = self.run_helper(SUSPEND_EXIT="5")
        self.assertEqual(result.returncode, 5)
        self.assertEqual(calls[-1], ["systemctl", "suspend"])


if __name__ == "__main__":
    unittest.main()
