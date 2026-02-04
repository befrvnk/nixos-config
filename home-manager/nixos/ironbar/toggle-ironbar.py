#!/usr/bin/env python3
"""
Ironbar toggle script for niri overview mode.
Shows ironbar only when niri's overview (expose) mode is active.
Uses Ironbar IPC commands to control visibility.
"""

from json import loads, dumps
from os import environ
from subprocess import Popen, PIPE, run
from socket import AF_UNIX, socket as Socket, SHUT_WR
from typing import TextIO
import sys
import time
import re
import threading

def send_ironbar_command(command: str, bar_name: str) -> None:
    """Send IPC command to ironbar to show/hide the bar."""
    ipc_socket_path = f"/run/user/{environ.get('UID', '1000')}/ironbar-ipc.sock"

    try:
        sock = Socket(AF_UNIX)
        sock.connect(ipc_socket_path)

        # Create the IPC command
        ipc_command = {
            "command": "bar",
            "subcommand": command,
            "name": bar_name
        }

        # Send command as minified JSON
        sock.send((dumps(ipc_command) + "\n").encode())
        sock.close()

    except Exception as e:
        print(f"Error sending IPC command: {e}", file=sys.stderr, flush=True)

def monitor_bar_names(proc: Popen, bar_names: list, bar_names_lock: threading.Lock) -> None:
    """Continuously monitor ironbar's stdout/stderr for new bars being created.

    Looks for lines like: "Initializing bar 'bar-20' on 'eDP-1'"
    Adds newly detected bars to the bar_names list.
    """
    def read_output(stream, name):
        for line in iter(stream.readline, b''):
            line_str = line.decode('utf-8', errors='ignore')
            # Print to our stdout/stderr
            print(line_str, end='', flush=True)

            # Try to extract bar name
            if 'Initializing bar' in line_str:
                match = re.search(r"Initializing bar '([^']+)'", line_str)
                if match:
                    bar_name = match.group(1)
                    with bar_names_lock:
                        if bar_name not in bar_names:
                            bar_names.append(bar_name)
                            print(f"Detected new bar: {bar_name}", flush=True)

    # Start threads to read stdout and stderr
    stdout_thread = threading.Thread(target=read_output, args=(proc.stdout, 'stdout'))
    stderr_thread = threading.Thread(target=read_output, args=(proc.stderr, 'stderr'))
    stdout_thread.daemon = True
    stderr_thread.daemon = True
    stdout_thread.start()
    stderr_thread.start()

def main() -> None:
    print("Starting ironbar toggle script...", flush=True)

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

    # Start ironbar process (starts visible by default)
    print("Starting ironbar...", flush=True)
    ironbar_proc: Popen = Popen(
        ["ironbar"],
        stdout=PIPE,
        stderr=PIPE
    )

    # Track all bar names dynamically
    bar_names = []
    bar_names_lock = threading.Lock()

    # Start monitoring ironbar output for bar names
    # This also starts threads to forward stdout/stderr
    monitor_bar_names(ironbar_proc, bar_names, bar_names_lock)

    # Give ironbar a moment to fully start and detect initial bar(s)
    time.sleep(0.5)

    # Check if ironbar crashed
    if ironbar_proc.poll() is not None:
        print(f"ERROR: Ironbar exited with code {ironbar_proc.returncode}", file=sys.stderr, flush=True)
        sys.exit(1)

    # Wait a bit more for initial bar detection
    for _ in range(15):  # Wait up to 1.5 seconds total
        with bar_names_lock:
            if bar_names:
                break
        time.sleep(0.1)

    with bar_names_lock:
        if not bar_names:
            print("WARNING: No bars detected, toggle may not work", file=sys.stderr, flush=True)
        else:
            print(f"Controlling bars: {bar_names}", flush=True)

    # Hide all bars initially (only show in overview)
    print("Hiding all bars initially...", flush=True)
    with bar_names_lock:
        for bar_name in bar_names:
            send_ironbar_command("hide", bar_name)

    def show_all_bars() -> None:
        """Send show command to all bars via IPC."""
        with bar_names_lock:
            for bar_name in bar_names:
                send_ironbar_command("show", bar_name)
        print(f"Sent show command to {len(bar_names)} bar(s)", flush=True)

    def hide_all_bars() -> None:
        """Send hide command to all bars via IPC."""
        with bar_names_lock:
            for bar_name in bar_names:
                send_ironbar_command("hide", bar_name)
        print(f"Sent hide command to {len(bar_names)} bar(s)", flush=True)

    def close_popup() -> None:
        """Close any open ironbar popup."""
        try:
            run(["ironbar", "bar", "main", "hide-popup"], capture_output=True)
            print("Closed popup", flush=True)
        except Exception as e:
            print(f"Error closing popup: {e}", file=sys.stderr, flush=True)

    # Track last state to avoid sending duplicate commands
    last_visible_state: bool | None = None

    print("Listening for niri overview events...", flush=True)
    try:
        for line in file:
            event = loads(line)
            overview_event = event.get("OverviewOpenedOrClosed")
            if overview_event is not None:
                is_open = overview_event.get("is_open", False)

                # Only send command if state actually changed
                if is_open != last_visible_state:
                    print(f"Overview {'opened' if is_open else 'closed'}", flush=True)
                    last_visible_state = is_open

                    if is_open:
                        show_all_bars()
                    else:
                        close_popup()
                        hide_all_bars()
                else:
                    print(f"Ignoring duplicate {'open' if is_open else 'close'} event", flush=True)
    except KeyboardInterrupt:
        print("\nShutting down ironbar toggle script...", flush=True)
        ironbar_proc.terminate()
    except Exception as e:
        print(f"Error in event loop: {e}", file=sys.stderr, flush=True)
        ironbar_proc.terminate()
        sys.exit(1)

if __name__ == "__main__":
    main()
