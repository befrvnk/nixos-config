#!/usr/bin/env python3
"""
Waybar toggle script for niri overview mode.
Shows waybar only when niri's overview (expose) mode is active.
"""

from json import loads
from os import environ
from signal import SIGUSR1
from subprocess import Popen, PIPE
from socket import AF_UNIX, socket, SHUT_WR
from select import poll, POLLIN
from time import time
import sys

def main():
    print("Starting waybar toggle script...", flush=True)

    # Connect to niri socket
    niri_socket = socket(AF_UNIX)
    try:
        niri_socket.connect(environ["NIRI_SOCKET"])
        print("Connected to niri socket", flush=True)
    except KeyError:
        print("Error: NIRI_SOCKET environment variable not set", file=sys.stderr, flush=True)
        sys.exit(1)
    except Exception as e:
        print(f"Error connecting to niri socket: {e}", file=sys.stderr, flush=True)
        sys.exit(1)

    file = niri_socket.makefile("rw")

    # Request event stream from niri
    file.write('"EventStream"')
    file.flush()
    niri_socket.shutdown(SHUT_WR)

    # Start waybar process
    print("Starting waybar...", flush=True)
    waybar_proc = Popen(
        ["waybar"],
        stdout=PIPE,
        stderr=PIPE,
        text=True
    )

    # Wait for waybar to be configured using non-blocking poll
    print("Waiting for waybar to initialize (non-blocking)...", flush=True)
    assert waybar_proc.stdout is not None

    poller = poll()
    poller.register(waybar_proc.stdout.fileno(), POLLIN)

    timeout_ms = 5000  # 5 second timeout
    start_time = time()
    configured = False

    while not configured and (time() - start_time) < (timeout_ms / 1000):
        # Poll with 100ms timeout for each iteration
        events = poller.poll(100)

        if events:
            # Data is available, read a line
            line = waybar_proc.stdout.readline()
            if line:
                print(f"Waybar: {line.strip()}", flush=True)
                if "[info] Bar configured" in line:
                    configured = True
                    print("Waybar configured!", flush=True)
                    break

    if not configured:
        print("Timeout waiting for waybar configuration, proceeding anyway...", flush=True)

    poller.unregister(waybar_proc.stdout.fileno())

    def toggle_waybar():
        """Send SIGUSR1 signal to waybar to toggle visibility."""
        try:
            waybar_proc.send_signal(SIGUSR1)
            print("Toggled waybar visibility", flush=True)
        except Exception as e:
            print(f"Error toggling waybar: {e}", file=sys.stderr, flush=True)

    # Track waybar visibility state
    waybar_visible = True  # Waybar starts visible

    # Hide waybar initially (it starts visible by default)
    print("Hiding waybar initially...", flush=True)
    toggle_waybar()
    waybar_visible = False

    # Listen for overview open/close events
    print("Listening for niri overview events...", flush=True)
    try:
        for line in file:
            event = loads(line)
            overview_event = event.get("OverviewOpenedOrClosed")
            if overview_event is not None:
                # Log the full event structure to understand it
                print(f"Full overview event: {overview_event}", flush=True)

                # Check if overview is now open (event uses 'is_open' key)
                overview_open = overview_event.get("is_open", False)
                print(f"Parsed overview state: is_open={overview_open}", flush=True)

                # Show waybar when overview is open, hide when closed
                should_be_visible = overview_open

                if should_be_visible != waybar_visible:
                    print(f"State change: {waybar_visible} -> {should_be_visible}", flush=True)
                    toggle_waybar()
                    waybar_visible = should_be_visible
                else:
                    print(f"No state change needed (already {waybar_visible})", flush=True)
    except KeyboardInterrupt:
        print("\nShutting down waybar toggle script...", flush=True)
        waybar_proc.terminate()
    except Exception as e:
        print(f"Error in event loop: {e}", file=sys.stderr, flush=True)
        waybar_proc.terminate()
        sys.exit(1)

if __name__ == "__main__":
    main()
