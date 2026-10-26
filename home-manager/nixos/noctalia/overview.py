"""Bridge the active Niri/Umbriel overview event stream to Noctalia V5 bar IPC."""

import glob
import json
import os
import socket
import subprocess
import sys

# Noctalia's IPC socket takes one "<cwd>\\x1e<command>" message per connection and answers
# with a short ack. The server dispatches on EOF, so the write half must be shut down
# right after sending; without that it waits ~100 ms for more input. Sending directly
# costs ~0.2 ms, while spawning the 38 MB client binary per command costs ~36 ms, which
# is what made the bar lag behind the overview transition.
COMMAND_SEPARATOR = b"\x1e"


def noctalia_sockets():
    """Locate the bar sockets; the per-display dmenu socket never matches."""
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        return []
    return sorted(glob.glob(os.path.join(runtime, "noctalia-wayland-*.sock")))


def send_via_socket(path, command, timeout=2.0):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(timeout)
        connection.connect(path)
        connection.sendall(os.getcwdb() + COMMAND_SEPARATOR + command.encode())
        connection.shutdown(socket.SHUT_WR)
        connection.recv(4096)


def send(noctalia, command):
    """Dispatch one command over the socket, falling back to the CLI if needed."""
    for path in noctalia_sockets():
        try:
            send_via_socket(path, command)
            return
        except OSError:
            continue  # socket vanished (Noctalia restarted); try the next one, then CLI
    subprocess.run([noctalia, "msg", command], check=True, timeout=5)


def apply_visibility(noctalia, is_open):
    """Hide panels too when leaving overview, so no popup remains orphaned."""
    # Hide the bar first when leaving: it is the part the user watches disappear.
    commands = ["bar-show"] if is_open else ["bar-hide", "panel-close"]
    for command in commands:
        send(noctalia, command)


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
