#!/usr/bin/env python3
"""
Waybar toggle script for niri overview mode.
Shows waybar only when niri's overview (expose) mode is active.
Uses SIGUSR1 (show) and SIGUSR2 (hide) for explicit state control.
"""

from json import loads
from os import environ
from signal import SIGUSR1, SIGUSR2
from subprocess import Popen, PIPE
from socket import AF_UNIX, socket as Socket, SHUT_WR
from time import time
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
    waybar_proc: Popen[str] = Popen(
        ["waybar"],
        stdout=PIPE,
        stderr=PIPE,
        text=True
    )

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

    # Debounce rapid events
    last_event_time: float = time()
    debounce_seconds: float = 0.2

    print("Listening for niri overview events...", flush=True)
    try:
        for line in file:
            event = loads(line)
            overview_event = event.get("OverviewOpenedOrClosed")
            if overview_event is not None:
                current_time = time()
                time_since_last = current_time - last_event_time

                # Debounce: only process if enough time passed
                if time_since_last >= debounce_seconds:
                    last_event_time = current_time

                    is_open = overview_event.get("is_open", False)
                    print(f"Overview {'opened' if is_open else 'closed'}", flush=True)

                    # Explicit show or hide based on overview state
                    if is_open:
                        show_waybar()
                    else:
                        hide_waybar()
                else:
                    print(f"Debouncing (waiting {debounce_seconds - time_since_last:.2f}s more)", flush=True)
    except KeyboardInterrupt:
        print("\nShutting down waybar toggle script...", flush=True)
        waybar_proc.terminate()
    except Exception as e:
        print(f"Error in event loop: {e}", file=sys.stderr, flush=True)
        waybar_proc.terminate()
        sys.exit(1)

if __name__ == "__main__":
    main()
