"""Unit tests for the overview bridge, without a live compositor or shell."""

import io
import subprocess
import unittest
from unittest.mock import MagicMock, call, patch

import overview


class OverviewTests(unittest.TestCase):
    @patch("overview.subprocess.run")
    def test_open_shows_bar(self, run):
        overview.apply_visibility("/bin/noctalia", True)
        run.assert_called_once_with(
            ["/bin/noctalia", "msg", "bar-show"], check=True, timeout=5
        )

    @patch("overview.subprocess.run")
    def test_close_hides_panel_before_bar(self, run):
        overview.apply_visibility("/bin/noctalia", False)
        self.assertEqual(
            run.call_args_list,
            [
                call(["/bin/noctalia", "msg", "panel-close"], check=True, timeout=5),
                call(["/bin/noctalia", "msg", "bar-hide"], check=True, timeout=5),
            ],
        )

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

    @patch("overview.subprocess.run", side_effect=subprocess.TimeoutExpired("noctalia", 5))
    def test_ipc_failure_propagates_for_systemd_restart(self, _run):
        with self.assertRaises(subprocess.TimeoutExpired):
            overview.apply_visibility("/bin/noctalia", True)


if __name__ == "__main__":
    unittest.main()
