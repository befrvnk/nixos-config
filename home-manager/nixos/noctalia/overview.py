"""Bridge the active Niri/Umbriel overview event stream to Noctalia V5 bar IPC."""

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


def select_backend(environment):
    desktop = environment.get("XDG_CURRENT_DESKTOP", "").lower().split(":")
    if "umbriel" in desktop:
        backend, key = "umbriel", "UMBRIEL_SOCKET"
    elif "niri" in desktop:
        backend, key = "niri", "NIRI_SOCKET"
    else:
        raise ValueError("No supported active compositor; refusing a stale socket")
    path = environment.get(key)
    if not path:
        raise ValueError(f"Active {backend} session has no {key}")
    return path, backend


def watch(noctalia, socket_path, backend="niri"):
    # Fail closed until the active compositor delivers its initial snapshot.
    apply_visibility(noctalia, False)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.connect(socket_path)
        if backend == "niri":
            connection.sendall(b'"EventStream"\n')
            connection.shutdown(socket.SHUT_WR)
        elif backend == "umbriel":
            connection.sendall(b'{"cmd":"subscribe","events":["overview"]}\n')
        else:
            raise ValueError(f"Unsupported overview backend: {backend}")
        with connection.makefile("r", encoding="utf-8") as events:
            last_state = None
            for line in events:
                event = json.loads(line)
                if backend == "niri":
                    overview = event.get("OverviewOpenedOrClosed")
                    if overview is None:
                        continue
                    is_open = overview["is_open"]
                else:
                    if "err" in event:
                        raise ConnectionError(f"Umbriel rejected overview subscription: {event['err']}")
                    if event.get("event") != "overview":
                        continue
                    is_open = event["data"]["open"]
                if not isinstance(is_open, bool):
                    raise ValueError("Invalid overview state")
                if is_open != last_state:
                    apply_visibility(noctalia, is_open)
                    last_state = is_open
    raise ConnectionError(f"{backend} event stream closed; reconnect via systemd")


if __name__ == "__main__":
    watch(sys.argv[1], *select_backend(os.environ))
