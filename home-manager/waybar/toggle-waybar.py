#!/usr/bin/env python3
"""
Waybar toggle script for niri overview mode.
Shows waybar only when niri's overview (expose) mode is active.
Uses SIGUSR1 (show) and SIGUSR2 (hide) for explicit state control.
"""

from json import loads
from os import environ
from signal import SIGUSR1, SIGUSR2
from subprocess import Popen
from socket import AF_UNIX, socket as Socket, SHUT_WR
from typing import TextIO
import sys

def main() -> None:
    print("Starting waybar toggle script...", flush=True)

    # Connect to niri socket
    niri_socket: Socket = Socket(AF_UNIX)
    try:
        niri_socket.connect(environ["NIRI_SOCKET"])
        print("Connected to niri socket", flush=True)
    except KeyError:
        print("Error: NIRI_SOCKET environment variable not set", file=sys.stderr, flush=True)
        sys.exit(1)
    except Exception as e:
        print(f"Error connecting to niri socket: {e}", file=sys.stderr, flush=True)
        sys.exit(1)

    file: TextIO = niri_socket.makefile("rw")

    # Request event stream from niri
    file.write('"EventStream"')
    file.flush()
    niri_socket.shutdown(SHUT_WR)

    # Start waybar process
    print("Starting waybar (starts hidden)...", flush=True)
    waybar_proc: Popen = Popen(
        ["waybar"],
        stdout=sys.stdout,
        stderr=sys.stderr
    )

    # Give waybar a moment to start
    import time
    time.sleep(0.5)

    # Check if waybar crashed immediately
    if waybar_proc.poll() is not None:
        print(f"ERROR: Waybar exited immediately with code {waybar_proc.returncode}", file=sys.stderr, flush=True)
        sys.exit(1)

    def show_waybar() -> None:
        """Send SIGUSR1 to waybar to show it."""
        try:
            waybar_proc.send_signal(SIGUSR1)
            print("Sent show signal (SIGUSR1) to waybar", flush=True)
        except Exception as e:
            print(f"Error showing waybar: {e}", file=sys.stderr, flush=True)

    def hide_waybar() -> None:
        """Send SIGUSR2 to waybar to hide it."""
        try:
            waybar_proc.send_signal(SIGUSR2)
            print("Sent hide signal (SIGUSR2) to waybar", flush=True)
        except Exception as e:
            print(f"Error hiding waybar: {e}", file=sys.stderr, flush=True)

    # Track last state to avoid sending duplicate signals
    last_visible_state: bool | None = None

    print("Listening for niri overview events...", flush=True)
    try:
        for line in file:
            event = loads(line)
            overview_event = event.get("OverviewOpenedOrClosed")
            if overview_event is not None:
                is_open = overview_event.get("is_open", False)

                # Only send signal if state actually changed
                if is_open != last_visible_state:
                    print(f"Overview {'opened' if is_open else 'closed'}", flush=True)
                    last_visible_state = is_open

                    # Explicit show or hide based on overview state
                    if is_open:
                        show_waybar()
                    else:
                        hide_waybar()
                else:
                    print(f"Ignoring duplicate {'open' if is_open else 'close'} event", flush=True)
    except KeyboardInterrupt:
        print("\nShutting down waybar toggle script...", flush=True)
        waybar_proc.terminate()
    except Exception as e:
        print(f"Error in event loop: {e}", file=sys.stderr, flush=True)
        waybar_proc.terminate()
        sys.exit(1)

if __name__ == "__main__":
    main()
