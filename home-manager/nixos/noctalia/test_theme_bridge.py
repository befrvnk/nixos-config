"""Theme-controller tests: all service, IPC and activation commands are mocked."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import theme_bridge as bridge


class ThemeBridgeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.runtime = self.root / "runtime"
        self.home = self.root / "home"
        self.state = self.root / "state.json"
        self.base = self.make_generation("base-home-manager-generation")
        self.mode = "light"
        self.calls = []
        self.activation_callback = None
        self.fail_activation = False
        self.fail_refresh = False
        for mode in ("dark", "light"):
            source = self.home / ".config/nushell" / f"theme-{mode}.nuon"
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(mode)
        self.runner = patch("theme_bridge.run", side_effect=self.fake_run)
        self.runner.start()
        self.addCleanup(self.runner.stop)

    def make_generation(self, name):
        base = self.root / name
        for mode in ("dark", "light"):
            script = base / "specialisation" / mode / "activate"
            script.parent.mkdir(parents=True)
            script.write_text("not executable: tests must mock activation")
        return base

    def fake_run(self, command, **kwargs):
        self.calls.append((command, kwargs))
        stdout = ""
        if command[:2] == ["systemctl", "show"]:
            stdout = "ActiveState=active\nJob=\n"
        elif command == ["noctalia", "msg", "theme-mode-get"]:
            stdout = self.mode + "\n"
        elif command[0] == "nix-store":
            stdout = str(self.base) + "\n"
        elif command[0].endswith("/activate"):
            if self.fail_activation:
                raise subprocess.CalledProcessError(1, command)
            if self.activation_callback:
                callback, self.activation_callback = self.activation_callback, None
                callback()
        elif command == ["awww", "query"] and self.fail_refresh:
            raise subprocess.CalledProcessError(1, command)
        return subprocess.CompletedProcess(command, 0, stdout=stdout)

    def process(self):
        bridge.process_requests(self.runtime, self.state, self.home, "noctalia", "awww",
                                {"dark": Path("dark.jpg"), "light": Path("light.jpg")},
                                "home-manager-test.service")

    def activations(self):
        return [(args, kwargs) for args, kwargs in self.calls if args[0].endswith("/activate")]

    def test_no_request_does_nothing(self):
        self.process()
        self.assertEqual(self.calls, [])

    def test_coalesces_requests_and_preserves_force_refresh(self):
        bridge.request(self.runtime, force=True)
        first = bridge.read_json(self.runtime / "request.json")
        bridge.request(self.runtime, refresh=True)
        latest = bridge.read_json(self.runtime / "request.json")
        self.assertNotEqual(first["id"], latest["id"])
        self.assertTrue(latest["force"])
        self.assertTrue(latest["refresh"])

    def test_selects_resolved_mode_and_avoids_reverse_control(self):
        bridge.request(self.runtime)
        self.process()
        actions = self.activations()
        self.assertEqual(len(actions), 1)
        self.assertEqual(actions[0][0], [str(self.base / "specialisation/light/activate")])
        self.assertEqual(actions[0][1]["env"]["NOCTALIA_THEME_BRIDGE_ACTIVE"], "1")
        self.assertFalse((self.runtime / "request.json").exists())
        self.assertEqual((self.home / ".local/state/nushell/theme.nuon").read_text(), "light")
        self.assertFalse(any("theme-mode-set" in args or "noctalia.service" in args
                             for args, _ in self.calls))

    def test_native_preference_sync_runs_after_activation_without_reverse_writes(self):
        bridge.request(self.runtime)
        self.process()
        commands = [args for args, _ in self.calls]
        activation_index = next(i for i, args in enumerate(commands) if args[0].endswith("/activate"))
        native_sync_index = commands.index(["noctalia", "msg", "templates-apply"])
        self.assertGreater(native_sync_index, activation_index)
        self.assertFalse(any(args[0] in ("dconf", "gsettings") for args in commands))
        self.assertFalse(any("theme-mode-set" in args for args in commands))

    def test_duplicate_mode_does_not_reactivate(self):
        bridge.request(self.runtime)
        self.process()
        bridge.request(self.runtime)
        self.process()
        self.assertEqual(len(self.activations()), 1)

    def test_normal_activation_force_request_reapplies_same_mode(self):
        bridge.request(self.runtime)
        self.process()
        bridge.request(self.runtime, force=True)
        self.process()
        self.assertEqual(len(self.activations()), 2)

    def test_new_base_generation_invalidates_cache(self):
        bridge.request(self.runtime)
        self.process()
        self.base = self.make_generation("new-home-manager-generation")
        bridge.request(self.runtime)
        self.process()
        self.assertEqual(len(self.activations()), 2)
        self.assertEqual(bridge.read_json(self.state)["generation"], str(self.base))

    def test_newer_event_during_activation_is_not_lost(self):
        def switch_to_dark():
            self.mode = "dark"
            bridge.request(self.runtime)
        self.activation_callback = switch_to_dark
        bridge.request(self.runtime)
        self.process()
        self.assertEqual(len(self.activations()), 2)
        self.assertEqual(bridge.read_json(self.state)["mode"], "dark")
        self.assertEqual((self.home / ".local/state/nushell/theme.nuon").read_text(), "dark")
        self.assertFalse((self.runtime / "request.json").exists())

    def test_hotplug_refresh_does_not_reactivate_or_restart_clients(self):
        bridge.request(self.runtime)
        self.process()
        count = len(self.calls)
        bridge.request(self.runtime, refresh=True)
        self.process()
        extra = [args for args, _ in self.calls[count:]]
        self.assertEqual(len(self.activations()), 1)
        self.assertTrue(any(args[:2] == ["awww", "img"] for args in extra))
        self.assertFalse(any("try-restart" in args for args in extra))

    def test_activation_failure_leaves_request_for_retry(self):
        self.fail_activation = True
        bridge.request(self.runtime)
        with self.assertRaises(subprocess.CalledProcessError):
            self.process()
        self.assertTrue((self.runtime / "request.json").exists())
        self.assertFalse(self.state.exists())

    def test_refresh_failure_retries_without_repeating_forced_activation(self):
        self.fail_refresh = True
        bridge.request(self.runtime, force=True)
        with self.assertRaises(subprocess.CalledProcessError):
            self.process()
        self.assertTrue(bridge.read_json(self.state)["refresh_pending"])
        self.fail_refresh = False
        self.process()
        self.assertEqual(len(self.activations()), 1)
        self.assertFalse(bridge.read_json(self.state)["refresh_pending"])
        self.assertFalse((self.runtime / "request.json").exists())

    def test_invalid_resolved_mode_never_activates(self):
        self.mode = "invalid"
        bridge.request(self.runtime)
        with self.assertRaises(ValueError):
            self.process()
        self.assertEqual(self.activations(), [])
        self.assertTrue((self.runtime / "request.json").exists())

    def test_ambiguous_generation_fails_without_activation(self):
        other = self.make_generation("other-home-manager-generation")
        with patch("theme_bridge.generation_for", side_effect=RuntimeError(f"ambiguous: {other}")):
            bridge.request(self.runtime)
            with self.assertRaises(RuntimeError):
                self.process()
        self.assertEqual(self.activations(), [])

    def test_busy_hm_unit_defers_activation(self):
        with patch("theme_bridge.run", return_value=subprocess.CompletedProcess(
                [], 0, stdout="ActiveState=activating\nJob=42\n")), patch("theme_bridge.time.sleep"):
            with self.assertRaises(TimeoutError):
                bridge.wait_for_activation("home-manager-test.service", attempts=2)


if __name__ == "__main__":
    unittest.main()
