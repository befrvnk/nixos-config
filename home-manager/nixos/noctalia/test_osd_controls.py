"""Native control wiring and mocked brightness/DDC tests. No live hardware calls."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class OsdControlTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.calls = self.root / "calls"
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        tools = self.root / "bin"
        tools.mkdir()
        header = f"#!{shutil.which('bash')}\nset -euo pipefail\n"
        scripts = {
            "brightnessctl": '''printf 'brightnessctl %s\\n' "$*" >> "$TEST_CALLS"
if [ "$1" = -q ]; then exit "${MOCK_BRIGHTNESS_FAILURE:-0}"; fi
if [ "$1" = -m ]; then printf 'amdgpu_bl1,backlight,100,%s%%,255\\n' "$MOCK_BRIGHTNESS"; fi
''',
            "noctalia": '''printf 'noctalia %s\\n' "$*" >> "$TEST_CALLS"
exit "${MOCK_OSD_FAILURE:-0}"
''',
            "ddcutil": '''printf 'ddcutil %s\\n' "$*" >> "$TEST_CALLS"
if [ -n "${MOCK_DDC_RETARGET:-}" ] && [ ! -e "$TEST_RETARGETED" ]; then
  printf '%s\\n' "$MOCK_DDC_RETARGET" > "$XDG_RUNTIME_DIR/brightness-ctl/target"
  touch "$TEST_RETARGETED"
fi
''',
        }
        for name, body in scripts.items():
            path = tools / name
            path.write_text(header + body)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                                HOME=str(self.root), XDG_RUNTIME_DIR=str(self.runtime),
                                TEST_CALLS=str(self.calls), TEST_RETARGETED=str(self.root / "retargeted"),
                                MOCK_BRIGHTNESS="42")
        self.integration = json.loads(Path(os.environ["OSD_INTEGRATION"]).read_text())

    def brightness(self, action):
        return subprocess.run([shutil.which("bash"), os.environ["BRIGHTNESS_CONTROL_SCRIPT"], *action],
                              env=self.environment, capture_output=True, text=True, timeout=10)

    def commands(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_native_volume_bindings_steps_and_caps_are_declared_without_running_them(self):
        bindings = self.integration["binds"]
        for key, command in (("XF86AudioRaiseVolume", "volume-up"),
                             ("XF86AudioLowerVolume", "volume-down")):
            args = bindings[key]["action"]["spawn"]
            self.assertTrue(args[0].endswith("/bin/noctalia"))
            self.assertEqual(args[1:], ["msg", command, "5%"])
        args = bindings["XF86AudioMute"]["action"]["spawn"]
        self.assertEqual(args[1:], ["msg", "volume-mute"])
        self.assertFalse(self.integration["audio"]["enable_overdrive"])
        self.assertEqual(self.integration["osd"]["position"], "bottom_center")
        self.assertEqual(self.integration["osd"]["position_vertical"], "bottom_center")
        kinds = self.integration["osd"]["kinds"]
        self.assertTrue(kinds["volume"] and kinds["volume_output"] and kinds["brightness"])
        self.assertFalse(kinds["volume_input"])
        self.assertFalse(kinds["lock_keys"])
        for key, action in (("XF86MonBrightnessUp", "raise"), ("XF86MonBrightnessDown", "lower")):
            self.assertEqual(bindings[key]["action"]["spawn"], ["brightness-ctl", action])
        self.assertFalse(self.calls.exists())

    def test_framework_audio_initialization_is_preserved_and_cache_init_removed(self):
        commands = [entry["command"] for entry in self.integration["startup"]]
        loopbacks = [args for args in commands if any("pw-loopback" in arg for arg in args)]
        self.assertEqual(len(loopbacks), 1)
        self.assertIn("timeout 0.5", loopbacks[0][-1])
        self.assertIn("media.class=Audio/Sink", loopbacks[0][-1])
        self.assertIn("node.target=@DEFAULT_AUDIO_SINK@", loopbacks[0][-1])
        self.assertFalse(any("volume-ctl" in arg for args in commands for arg in args))

    def test_brightness_still_changes_internal_and_syncs_ddc_with_display_only_osd(self):
        for action, step in (("raise", "5%+"), ("lower", "5%-")):
            self.calls.unlink(missing_ok=True)
            result = self.brightness([action])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.commands(), [f"brightnessctl -q set {step}", "brightnessctl -m",
                                               "noctalia msg brightness-osd 42%", "ddcutil setvcp 10 42"])
        self.assertEqual((self.runtime / "brightness-ctl/target").read_text(), "42\n")
        self.assertFalse((self.runtime / "brightness-ctl/ddc.lock").exists())

    def test_missing_native_osd_does_not_block_hardware_sync(self):
        self.environment["MOCK_OSD_FAILURE"] = "1"
        result = self.brightness(["raise"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ddcutil setvcp 10 42", self.commands())

    def test_failed_internal_change_does_not_show_or_sync_stale_brightness(self):
        self.environment["MOCK_BRIGHTNESS_FAILURE"] = "2"
        result = self.brightness(["raise"])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.commands(), ["brightnessctl -q set 5%+"])
        self.assertFalse((self.runtime / "brightness-ctl/target").exists())

    def test_external_worker_catches_up_when_target_changes(self):
        self.environment["MOCK_DDC_RETARGET"] = "75"
        result = self.brightness(["raise"])
        self.assertEqual(result.returncode, 0, result.stderr)
        ddc = [line for line in self.commands() if line.startswith("ddcutil")]
        self.assertEqual(ddc, ["ddcutil setvcp 10 42", "ddcutil setvcp 10 75"])
        self.assertFalse((self.runtime / "brightness-ctl/ddc.lock").exists())

    def test_existing_worker_lock_avoids_second_ddc_worker(self):
        state = self.runtime / "brightness-ctl"
        state.mkdir()
        (state / "ddc.lock").touch()
        result = self.brightness(["lower"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("noctalia msg brightness-osd 42%", self.commands())
        self.assertFalse(any(line.startswith("ddcutil") for line in self.commands()))
        self.assertTrue((state / "ddc.lock").exists())

    def test_invalid_actions_do_not_touch_hardware(self):
        for args in ([], ["invalid"]):
            result = self.brightness(args)
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [])


if __name__ == "__main__":
    unittest.main()
