"""Bridge Niri's overview event stream to Noctalia V5's bar IPC."""

import json
import os
import socket
import subprocess
import sys


def apply_visibility(noctalia, is_open):
    """Hide panels too when leaving overview, so no popup remains orphaned."""
    commands = ["bar-show"] if is_open else ["panel-close", "bar-hide"]
    for command in commands:
        subprocess.run([noctalia, "msg", command], check=True, timeout=5)


def watch(noctalia, socket_path):
    # Fail closed until Niri delivers its initial overview-state snapshot.
    apply_visibility(noctalia, False)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.connect(socket_path)
        connection.sendall(b'"EventStream"\n')
        connection.shutdown(socket.SHUT_WR)
        with connection.makefile("r", encoding="utf-8") as events:
            last_state = None
            for line in events:
                event = json.loads(line)
                overview = event.get("OverviewOpenedOrClosed")
                if overview is None:
                    continue
                is_open = overview["is_open"]
                if is_open != last_state:
                    apply_visibility(noctalia, is_open)
                    last_state = is_open
    raise ConnectionError("Niri event stream closed; reconnect via systemd")


if __name__ == "__main__":
    watch(sys.argv[1], os.environ["NIRI_SOCKET"])
