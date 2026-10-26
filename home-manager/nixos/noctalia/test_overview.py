"""Unit tests for the overview bridge, without a live compositor or shell."""

import io
import os
import socket
import subprocess
import unittest
from unittest.mock import MagicMock, call, patch

import overview


class OverviewTests(unittest.TestCase):
    @patch("overview.noctalia_sockets", return_value=[])
    @patch("overview.subprocess.run")
    def test_open_shows_bar_via_cli_fallback(self, run, _sockets):
        overview.apply_visibility("/bin/noctalia", True)
        run.assert_called_once_with(
            ["/bin/noctalia", "msg", "bar-show"], check=True, timeout=5
        )

    @patch("overview.noctalia_sockets", return_value=[])
    @patch("overview.subprocess.run")
    def test_close_hides_bar_before_panel(self, run, _sockets):
        overview.apply_visibility("/bin/noctalia", False)
        self.assertEqual(
            run.call_args_list,
            [
                call(["/bin/noctalia", "msg", "bar-hide"], check=True, timeout=5),
                call(["/bin/noctalia", "msg", "panel-close"], check=True, timeout=5),
            ],
        )

    @patch("overview.send_via_socket")
    @patch(
        "overview.noctalia_sockets",
        return_value=["/run/user/1000/noctalia-wayland-0.sock"],
    )
    @patch("overview.subprocess.run")
    def test_bar_commands_prefer_the_socket(self, run, _sockets, send_socket):
        overview.apply_visibility("/bin/noctalia", False)
        self.assertEqual(
            [args[0][1] for args in send_socket.call_args_list],
            ["bar-hide", "panel-close"],
        )
        run.assert_not_called()

    @patch("overview.send_via_socket", side_effect=OSError("socket gone"))
    @patch(
        "overview.noctalia_sockets",
        return_value=["/run/user/1000/noctalia-wayland-0.sock"],
    )
    @patch("overview.subprocess.run")
    def test_socket_failure_falls_back_to_cli(self, run, _sockets, _send):
        overview.apply_visibility("/bin/noctalia", True)
        run.assert_called_once_with(
            ["/bin/noctalia", "msg", "bar-show"], check=True, timeout=5
        )

    @patch("overview.socket.socket")
    def test_socket_payload_frames_cwd_and_closes_write_side(self, factory):
        connection = factory.return_value.__enter__.return_value
        overview.send_via_socket("/run/user/1000/noctalia-wayland-0.sock", "bar-hide")
        connection.connect.assert_called_once_with(
            "/run/user/1000/noctalia-wayland-0.sock"
        )
        self.assertEqual(
            connection.sendall.call_args[0][0],
            os.getcwdb() + b"\x1e" + b"bar-hide",
        )
        connection.shutdown.assert_called_once_with(socket.SHUT_WR)
        connection.recv.assert_called_once_with(4096)

    @patch("overview.glob.glob", return_value=["/run/user/1000/noctalia-wayland-0.sock"])
    @patch("overview.os.environ", {"XDG_RUNTIME_DIR": "/run/user/1000"})
    def test_socket_discovery_targets_bar_sockets_only(self, glob_mock):
        overview.noctalia_sockets()
        glob_mock.assert_called_once_with(
            "/run/user/1000/noctalia-wayland-*.sock"
        )

    @patch("overview.os.environ", {})
    def test_socket_discovery_without_runtime_dir_is_empty(self):
        self.assertEqual(overview.noctalia_sockets(), [])

    @patch("overview.socket.socket")
    @patch("overview.apply_visibility")
    def test_stream_initial_state_duplicates_and_eof(self, apply, socket_factory):
        connection = MagicMock()
        socket_factory.return_value.__enter__.return_value = connection
        events = (
            '{"Ok":"Handled"}\n'
            '{"OverviewOpenedOrClosed":{"is_open":true}}\n'
            '{"OverviewOpenedOrClosed":{"is_open":true}}\n'
            '{"WindowsChanged":{"windows":[]}}\n'
            '{"OverviewOpenedOrClosed":{"is_open":false}}\n'
        )
        connection.makefile.return_value = io.StringIO(events)
        with self.assertRaises(ConnectionError):
            overview.watch("/bin/noctalia", "/tmp/niri.sock")
        self.assertEqual(
            apply.call_args_list,
            [call("/bin/noctalia", False), call("/bin/noctalia", True), call("/bin/noctalia", False)],
        )
        connection.connect.assert_called_once_with("/tmp/niri.sock")
        connection.sendall.assert_called_once_with(b'"EventStream"\n')

    def test_backend_selection_uses_active_desktop_not_stale_other_socket(self):
        environment = {"NIRI_SOCKET": "/old-niri", "UMBRIEL_SOCKET": "/new-umbriel",
                       "XDG_CURRENT_DESKTOP": "Umbriel"}
        self.assertEqual(overview.select_backend(environment), ("/new-umbriel", "umbriel"))
        environment["XDG_CURRENT_DESKTOP"] = "niri"
        self.assertEqual(overview.select_backend(environment), ("/old-niri", "niri"))

    def test_missing_active_or_unknown_desktop_never_falls_back_to_another_socket(self):
        for environment in ({"XDG_CURRENT_DESKTOP": "umbriel", "NIRI_SOCKET": "/old"},
                            {"NIRI_SOCKET": "/old"}, {"XDG_CURRENT_DESKTOP": "unknown"}):
            with self.subTest(environment=environment), self.assertRaises(ValueError):
                overview.select_backend(environment)

    @patch("overview.socket.socket")
    @patch("overview.apply_visibility")
    def test_umbriel_subscription_initial_state_duplicates_and_close(self, apply, factory):
        connection = factory.return_value.__enter__.return_value
        connection.makefile.return_value = io.StringIO(
            '{"ok":true}\n'
            '{"event":"overview","data":{"open":false}}\n'
            '{"event":"overview","data":{"open":true}}\n'
            '{"event":"overview","data":{"open":true}}\n'
            '{"event":"windows","data":{}}\n'
            '{"event":"overview","data":{"open":false}}\n')
        with self.assertRaises(ConnectionError):
            overview.watch("/bin/noctalia", "/private/umbriel", "umbriel")
        connection.sendall.assert_called_once_with(b'{"cmd":"subscribe","events":["overview"]}\n')
        connection.shutdown.assert_not_called()  # Umbriel subscriptions stay bidirectional.
        self.assertEqual(apply.call_args_list, [call("/bin/noctalia", False),
            call("/bin/noctalia", False), call("/bin/noctalia", True), call("/bin/noctalia", False)])

    @patch("overview.socket.socket")
    @patch("overview.apply_visibility")
    def test_umbriel_rejection_never_shows_bar(self, apply, factory):
        factory.return_value.__enter__.return_value.makefile.return_value = io.StringIO('{"err":"rejected"}\n')
        with self.assertRaises(ConnectionError):
            overview.watch("/bin/noctalia", "/private/umbriel", "umbriel")
        apply.assert_called_once_with("/bin/noctalia", False)

    @patch("overview.socket.socket")
    @patch("overview.apply_visibility")
    def test_non_boolean_overview_state_is_not_truthy_visibility(self, apply, factory):
        factory.return_value.__enter__.return_value.makefile.return_value = io.StringIO(
            '{"event":"overview","data":{"open":"false"}}\n')
        with self.assertRaises(ValueError):
            overview.watch("/bin/noctalia", "/private/umbriel", "umbriel")
        apply.assert_called_once_with("/bin/noctalia", False)

    @patch("overview.noctalia_sockets", return_value=[])
    @patch("overview.subprocess.run", side_effect=subprocess.TimeoutExpired("noctalia", 5))
    def test_ipc_failure_propagates_for_systemd_restart(self, _run, _sockets):
        with self.assertRaises(subprocess.TimeoutExpired):
            overview.apply_visibility("/bin/noctalia", True)


if __name__ == "__main__":
    unittest.main()
