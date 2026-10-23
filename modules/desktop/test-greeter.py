"""Private environment/config fixtures; never start the greeter or authenticate."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


class GreeterChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.policy = json.loads(Path(os.environ["GREETER_POLICY"]).read_text())
        self.bash = shutil.which("bash")
        self.environment = {
            "HOME": str(self.root), "PATH": os.environ["PATH"],
            "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
        }
        self.fake = self.root / "frontend"
        self.fake.write_text(f"#!{self.bash}\n" + '''
printf '%s\\n' "$XDG_DATA_DIRS" "$XKB_CONFIG_ROOT" "$XKB_DEFAULT_MODEL" "$PATH"
''')
        self.fake.chmod(0o755)
        source = Path(self.policy["command"]).read_text()
        actual = self.policy["frontend"]
        self.assertIn(actual, source)
        self.script = self.root / "session.sh"
        self.script.write_text(source.replace(actual, str(self.fake)))

    def run_environment(self, **extra):
        result = subprocess.run([self.bash, str(self.script)],
                                env=dict(self.environment, **extra),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def test_password_entry_is_required_to_start_authentication(self):
        config = tomllib.loads(Path(self.policy["settingsFile"]).read_text())
        self.assertIs(config["auth"]["allow_empty_password"], False)
        self.assertEqual(config["session"]["default"], "niri")
        self.assertEqual(config["keyboard"]["layout"], "us-umlauts")
        self.assertEqual(config["keyboard"]["options"], "lv3:ralt_switch")
        self.assertNotIn("user", config)  # Keep normal account selection, not auto-login.
        self.assertNotIn("appearance", config)  # Don't pin over later authorized sync.

    def test_other_authentication_stacks_and_safe_session_defaults_are_unchanged(self):
        for name, text in self.policy["pam"].items():
            if name != "greetd":
                with self.subTest(service=name):
                    self.assertEqual(text, self.policy["referencePam"][name])
        self.assertTrue(self.policy["keyring"])
        self.assertEqual(self.policy["passwordlessSyncUsers"], [])
        self.assertFalse(self.policy["autologin"])
        self.assertFalse(self.policy["restartIfChanged"])
        self.assertEqual(self.policy["user"], "greeter")

    @staticmethod
    def pam_rows(text, kind):
        return [line.split(" #", 1)[0].strip() for line in text.splitlines()
                if line.startswith(kind + " ")]

    def test_greetd_requires_password_then_caches_same_token_for_keyring(self):
        rows = self.pam_rows(self.policy["pam"]["greetd"], "auth")
        self.assertEqual(rows, self.policy["expectedGreetdAuth"])
        self.assertFalse(any(word in row for row in rows
                             for word in ("nullok", "pam_permit", "pam_fprintd", "substack", "include")))
        self.assertIn("auth substack login", self.pam_rows(self.policy["referencePam"]["greetd"], "auth"))

    def test_greetd_account_password_and_session_stacks_remain_unchanged(self):
        for kind in ("account", "password", "session"):
            with self.subTest(kind=kind):
                self.assertEqual(self.pam_rows(self.policy["pam"]["greetd"], kind),
                                 self.pam_rows(self.policy["referencePam"]["greetd"], kind))
        # The retained session include owns keyring daemon startup after auth caching.
        self.assertIn("session include login", self.pam_rows(self.policy["pam"]["greetd"], "session"))
        self.assertTrue(any("pam_gnome_keyring.so auto_start" in row
                            for row in self.pam_rows(self.policy["pam"]["login"], "session")))

    def test_wrapper_exports_scoped_session_and_custom_keyboard_paths(self):
        data, xkb, model, path = self.run_environment()
        self.assertEqual(data, self.policy["desktops"] + "/share:/run/current-system/sw/share:/usr/local/share:/usr/share")
        self.assertEqual(xkb, self.policy["xkbRoot"])
        self.assertEqual(model, self.policy["model"])
        self.assertEqual(path, self.policy["sessionBinPath"] + ":" + self.environment["PATH"])
        self.assertTrue((Path(xkb) / "symbols/us-umlauts").is_file())
        self.assertTrue(any(Path(directory, "niri-session").is_file()
                            for directory in self.policy["sessionBinPath"].split(":")))

    def test_wrapper_preserves_existing_data_dirs_and_overrides_wrong_xkb_root(self):
        data, xkb, _, _ = self.run_environment(XDG_DATA_DIRS="/fixture/data:/fixture/share",
                                              XKB_CONFIG_ROOT="/wrong")
        self.assertEqual(data, self.policy["desktops"] + "/share:/fixture/data:/fixture/share")
        self.assertEqual(xkb, self.policy["xkbRoot"])

    def test_installed_binary_discovers_niri_without_display_or_authentication(self):
        # Source-reviewed early CLI dispatch: sessions exits before logging/Wayland/auth.
        data, _, _, path = self.run_environment()
        result = subprocess.run([self.policy["binary"], "sessions"],
                                env=dict(self.environment, XDG_DATA_DIRS=data, PATH=path),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Niri", result.stdout.splitlines())
        desktop = Path(self.policy["desktops"]) / "share/wayland-sessions/niri.desktop"
        self.assertIn("Exec=niri-session", desktop.read_text())

    def test_real_custom_keymap_compiles_without_any_device(self):
        _, xkb, model, _ = self.run_environment()
        config = tomllib.loads(Path(self.policy["settingsFile"]).read_text())
        keyboard = config["keyboard"]
        result = subprocess.run([os.environ["GREETER_KEYMAP_PROBE"]],
            env=dict(self.environment, XKB_CONFIG_ROOT=xkb, XKB_DEFAULT_MODEL=model,
                     GREETER_LAYOUT=keyboard["layout"], GREETER_VARIANT=keyboard["variant"],
                     GREETER_OPTIONS=keyboard["options"]), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
