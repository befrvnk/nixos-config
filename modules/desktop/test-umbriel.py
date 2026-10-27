"""Offline config/render/discovery and private session-wrapper fixtures only."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest


class UmbrielTrialChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.policy = json.loads(Path(os.environ["UMBRIEL_POLICY"]).read_text())
        self.home = self.root / "home"
        self.home.mkdir()
        self.config_home = self.home / ".config"
        self.config = self.config_home / "umbriel/config.toml"
        self.config.parent.mkdir(parents=True)
        self.target = self.root / "managed.toml"
        self.target.write_text(Path(self.policy["config"]).read_text().replace(
            self.policy["configHome"], str(self.config_home)))
        self.target.chmod(0o444)
        self.config.symlink_to(self.target)
        self.environment = {"HOME": str(self.home), "PATH": os.environ["PATH"],
                            "XDG_CONFIG_HOME": str(self.config_home),
                            "XDG_STATE_HOME": str(self.root / "state"),
                            "XDG_CACHE_HOME": str(self.root / "cache"),
                            "XKB_CONFIG_ROOT": self.policy["settings"]["environment"]["XKB_CONFIG_ROOT"]}
        self.binary = str(Path(self.policy["package"]) / "bin/umbriel")

    def validate(self, expected=0):
        # Source-reviewed early dispatch, before any compositor/display initialization.
        result = subprocess.run([self.binary, "config", "validate", "-c", str(self.config)],
            env=self.environment, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_real_binary_validates_main_with_missing_optional_colors(self):
        self.validate()

    def test_maintained_native_template_two_modes_leaves_main_readonly(self):
        template = Path(self.policy["noctorTemplate"]["input_path"])
        roles = set(re.findall(r"colors\.([a-z_0-9]+)\.default\.hex_stripped", template.read_text()))
        fixture = self.root / "palette.json"
        fixture.write_text(json.dumps({mode: {role: color for role in roles}
                                      for mode, color in (("dark", "#123456"), ("light", "#abcdef"))}))
        before = self.target.read_bytes()
        output = self.config.parent / "noctalia.toml"
        for mode in ("dark", "light"):
            result = subprocess.run([self.policy["native"], "theme", "--theme-json", str(fixture),
                "--both", "--default-mode", mode, "--render", f"{template}:{output}"],
                env=self.environment, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("{{", output.read_text())
            self.validate()
        self.assertEqual(self.target.read_bytes(), before)
        self.assertTrue(self.config.is_symlink())
        self.assertNotIn("post_hook", self.policy["noctorTemplate"])

    def test_invalid_optional_data_is_rejected_not_silently_ignored(self):
        (self.config.parent / "noctalia.toml").write_text("this is [invalid")
        self.validate(expected=1)

    def test_bindings_keep_existing_keys_and_guarded_hardware_paths(self):
        binds = self.policy["settings"]["keybinds"]
        def converted(name):
            return name.replace("WheelScroll", "Wheel")
        self.assertEqual(set(binds), {converted(name) for name in self.policy["originalBindings"]} | {"Alt+Tab"})
        self.assertIn(self.policy["safeSuspend"], binds["Mod+Shift+S"]["action"])
        self.assertIn("session", binds["Mod+Shift+X"]["action"])
        self.assertIn("volume-up", binds["XF86AudioRaiseVolume"]["action"])
        self.assertIn("5%", binds["XF86AudioRaiseVolume"]["action"])
        self.assertIn("brightness-ctl", binds["XF86MonBrightnessUp"]["action"])
        self.assertEqual(binds["Mod+Shift+D"]["action"], "output-toggle:eDP-1")
        self.assertFalse(any(re.fullmatch("F[0-9]+", key) for key in binds))
        for index in range(1, 10):
            self.assertEqual(binds[f"Mod+{index}"]["action"], f"workspace-switch:{index}")

    def test_alt_tab_uses_native_held_switcher_without_repeat_or_locked_permission(self):
        bind = self.policy["settings"]["keybinds"]["Alt+Tab"]
        self.assertEqual(bind["action"], "spawn:" + self.policy["native"] + " msg window-switcher hold")
        self.assertIs(bind["repeat"], False)
        self.assertFalse(bind.get("allow_when_locked", False))
        self.assertNotIn("Alt+Shift+Tab", self.policy["settings"]["keybinds"])

    def test_layout_overview_and_audio_init_preserve_essential_policy(self):
        settings = self.policy["settings"]
        self.assertEqual(settings["layout"]["mode"], "scrolling")
        self.assertEqual(settings["layout"]["gap"], 12)
        self.assertEqual(settings["appearance"]["corner_radius"], 16)
        self.assertEqual(settings["appearance"]["border_width"], 4)
        self.assertFalse(settings["overview"]["workspace_wallpaper"])
        self.assertFalse(settings["overview"]["background_blur"])
        self.assertEqual(settings["colors"]["overview"]["workspace_background"], "#00000000")
        self.assertNotIn("events", settings)  # Logind/root lid management remains sole owner.
        self.assertEqual(settings["input"]["keyboard"]["layout"], "us-umlauts")
        startup = settings["general"]["autostart"]
        self.assertEqual(len(startup), 1)
        script = Path(startup[0]).read_text()
        self.assertIn("pw-loopback", script)
        self.assertIn("timeout 0.5", script)
        self.assertNotIn("xwayland-satellite", " ".join(startup))
        self.assertNotIn("noctalia", " ".join(startup))  # Native shell starts once through systemd.

    def test_both_desktop_sessions_exist_and_trial_uses_profile_wrapper(self):
        directory = Path(self.policy["sessions"]) / "share/wayland-sessions"
        self.assertTrue((directory / "niri.desktop").is_file())
        umbrella = (directory / "umbriel.desktop").read_text()
        self.assertIn("Name=Umbriel", umbrella)
        self.assertIn("Exec=" + self.policy["launcher"], umbrella)
        self.assertEqual(set(self.policy["overviewConditions"]),
                         {"WAYLAND_DISPLAY", "|NIRI_SOCKET", "|UMBRIEL_SOCKET"})

    def test_portal_interfaces_match_desktop_routing_without_bus_calls(self):
        text = (Path(self.policy["portal"]) / "share/xdg-desktop-portal/portals/umbriel.portal").read_text()
        for interface in ("InputCapture", "ScreenCast", "Screenshot"):
            name = "org.freedesktop.impl.portal." + interface
            self.assertIn(name, text)
            self.assertEqual(self.policy["portalRouting"][name], "umbriel")
        self.assertEqual(self.policy["portalRouting"]["org.freedesktop.impl.portal.Settings"], "gtk")
        self.assertIn("UseIn=umbriel", text)

    def make_launcher_fixture(self, profile=True, real=False):
        profiles = self.root / "profiles"
        events = self.root / "events"
        user = subprocess.check_output([self.policy["coreutils"] + "/bin/id", "-un"], text=True).strip()
        if profile:
            file = profiles / user / "etc/profile.d/hm-session-vars.sh"
            file.parent.mkdir(parents=True)
            contents = Path(self.policy["homeVars"]).read_text() if real else ""
            file.write_text(contents + "\nexport FIXTURE_HM_VALUE=loaded\n")
        systemd = self.root / "systemd/bin"
        systemd.mkdir(parents=True)
        fake_systemctl = systemd / "systemctl"
        fake_systemctl.write_text(f"#!{sys.executable}\n" + '''
import os, sys
with open(os.environ["FIXTURE_EVENTS"], "a") as log:
    log.write("systemctl " + " ".join(sys.argv[1:]) + "\\n")
''')
        fake_systemctl.chmod(0o755)
        native = self.root / "native"
        (native / "bin").mkdir(parents=True)
        fake = native / "bin/start-umbriel"
        fake.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
with open(os.environ["FIXTURE_EVENTS"], "a") as log:
    log.write("native " + " ".join(sys.argv[1:]) + "\\n")
print(json.dumps({"hm": os.environ.get("FIXTURE_HM_VALUE"),
                  "niri": os.environ.get("NIRI_SOCKET"), "args": sys.argv[1:],
                  "xkb": os.environ.get("XKB_CONFIG_ROOT")}))
''')
        fake.chmod(0o755)
        source = Path(self.policy["launcher"]).read_text().replace("/etc/profiles/per-user", str(profiles))
        source = source.replace(self.policy["systemd"], str(fake_systemctl))
        # The wrapper intentionally execs the unmodified distribution launcher's package.
        original = re.search(r"exec (\S+)/bin/start-umbriel", source).group(1)
        source = source.replace(original, str(native))
        script = self.root / "launcher.sh"
        script.write_text(source)
        return subprocess.run([shutil.which("bash"), str(script), "argument with spaces"],
            env=dict(self.environment, SHELL="/fixture/nu", NIRI_SOCKET="/stale/niri",
                     FIXTURE_EVENTS=str(events),
                     XKB_CONFIG_ROOT="/fixture/unpatched"),
            capture_output=True, text=True, timeout=10)

    def test_nushell_session_wrapper_loads_hm_before_native_launcher_without_starting_it(self):
        result = self.make_launcher_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data, {"hm": "loaded", "niri": None, "args": ["argument with spaces"],
                                "xkb": self.policy["settings"]["environment"]["XKB_CONFIG_ROOT"]})

    def test_launcher_clears_stale_graphical_session_before_native_launcher(self):
        result = self.make_launcher_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = (self.root / "events").read_text().splitlines()
        self.assertEqual(events[0], "systemctl --user stop graphical-session.target")
        self.assertEqual(events[1], "native argument with spaces")

    def test_real_generated_hm_profile_supports_unset_optional_environment(self):
        result = self.make_launcher_fixture(real=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["hm"], "loaded")

    def test_missing_hm_profile_fails_instead_of_starting_partial_environment(self):
        result = self.make_launcher_fixture(profile=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("environment is unavailable", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
