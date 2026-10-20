"""Temporary one-way Noctalia -> prebuilt Home Manager theme adapter.

Requests are atomic files consumed by a systemd PathExists/oneshot pair. No
persistent poller, Nix rebuild, Noctalia restart, or reverse mode write is used.
"""

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        json.dump(value, output)
    os.replace(temporary, path)


def read_json(path):
    if not path.exists():
        return {}
    return json.loads(path.read_text())


@contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def request(runtime, *, force=False, refresh=False):
    with locked(runtime / "request.lock"):
        previous = read_json(runtime / "request.json")
        atomic_json(runtime / "request.json", {
            "id": uuid.uuid4().hex,
            "force": force or previous.get("force", False),
            "refresh": refresh or previous.get("refresh", False),
        })


def run(command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def resolved_mode(noctalia):
    mode = run([noctalia, "msg", "theme-mode-get"], capture_output=True,
               text=True, timeout=10).stdout.strip()
    if mode not in ("dark", "light"):
        raise ValueError(f"Invalid resolved Noctalia mode: {mode!r}")
    return mode


def wait_for_activation(unit, attempts=240):
    # This is the SYSTEM Home Manager activation unit, not a user unit. Wait
    # before acquiring our shared activation lock; the HM hook never waits on us.
    for _ in range(attempts):
        response = run(["systemctl", "show", unit, "-p", "ActiveState", "-p", "Job"],
                       capture_output=True, text=True, timeout=10).stdout
        properties = dict(line.split("=", 1) for line in response.splitlines() if "=" in line)
        if (properties.get("ActiveState") in ("active", "inactive")
                and properties.get("Job", "") in ("", "0")):
            return
        time.sleep(0.5)
    raise TimeoutError(f"{unit} did not finish; theme activation deferred")


def generation_for(mode):
    closure = run(["nix-store", "--query", "--requisites", "/run/current-system"],
                  capture_output=True, text=True, timeout=60).stdout.splitlines()
    candidates = [Path(path) for path in closure
                  if path.endswith("-home-manager-generation")
                  and (Path(path) / "specialisation" / mode / "activate").is_file()]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one Home Manager base generation, found {len(candidates)}")
    return candidates[0]


def refresh_clients(mode, home, awww, wallpapers):
    # All output paths are user-writable. App configuration itself stays managed
    # by the selected prebuilt HM specialisation during this compatibility phase.
    source = home / ".config" / "nushell" / f"theme-{mode}.nuon"
    destination = home / ".local" / "state" / "nushell" / "theme.nuon"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as output:
        output.write(source.read_bytes())
        temporary = Path(output.name)
    os.replace(temporary, destination)

    run([awww, "query"], capture_output=True, timeout=10)
    run([awww, "img", str(wallpapers[mode]), "--transition-type", "simple",
         "--transition-duration", "1"], timeout=30)


def process_requests(runtime, state_path, home, noctalia, awww, wallpapers, hm_unit):
    while read_json(runtime / "request.json"):
        wait_for_activation(hm_unit)
        # The same lock is held by ordinary HM activation hooks, so even a
        # rebuild beginning after our initial wait cannot race linkGeneration.
        with locked(runtime / "activation.lock"):
            pending = read_json(runtime / "request.json")
            if not pending:
                return
            mode = resolved_mode(noctalia)
            base = generation_for(mode)
            try:
                applied = read_json(state_path)
            except (ValueError, OSError):
                applied = {}  # This is only a cache, not user preference.
            changed = applied.get("generation") != str(base) or applied.get("mode") != mode
            forced = pending.get("force", False) and applied.get("request") != pending["id"]
            if changed or forced:
                print(f"Applying prebuilt {mode} app theme from {base}", flush=True)
                environment = dict(os.environ, NOCTALIA_THEME_BRIDGE_ACTIVE="1")
                run([str(base / "specialisation" / mode / "activate")], env=environment)
                # Record activation before optional UI refresh. A refresh failure
                # retries without repeating the same forced activation.
                applied = {"generation": str(base), "mode": mode, "request": pending["id"], "refresh_pending": True}
                atomic_json(state_path, applied)
            retry_refresh = applied.get("refresh_pending", False)
            if changed or forced or retry_refresh:
                # Initial removal of an HM-managed dconf key resets it once.
                # Let Noctalia reassert its own preference through its native
                # template pipeline; this neither changes mode nor fires palette hooks.
                run([noctalia, "msg", "templates-apply"], timeout=10)
                run(["systemctl", "--user", "try-restart", "swayosd.service"], timeout=60)
            if changed or forced or retry_refresh or pending.get("refresh", False):
                refresh_clients(mode, home, awww, wallpapers)
                atomic_json(state_path, {**applied, "refresh_pending": False})
                print(f"Refreshed {mode} wallpaper and app-theme clients", flush=True)

        # A newer event survives. PathExists also catches a request arriving
        # between this unlink and service exit, so no final-edge event is lost.
        with locked(runtime / "request.lock"):
            current = read_json(runtime / "request.json")
            if current.get("id") == pending["id"]:
                (runtime / "request.json").unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("request", "run"))
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    runtime_root = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    runtime = runtime_root / "noctalia-theme"
    if args.action == "request":
        request(runtime, force=args.force, refresh=args.refresh)
        return
    home = Path.home()
    state_root = Path(os.environ.get("XDG_STATE_HOME", home / ".local" / "state"))
    process_requests(
        runtime, state_root / "noctalia" / "theme-bridge.json", home,
        os.environ["NOCTALIA_COMMAND"], os.environ["NOCTALIA_AWWW"],
        {"light": Path(os.environ["NOCTALIA_WALLPAPER_LIGHT"]),
         "dark": Path(os.environ["NOCTALIA_WALLPAPER_DARK"])},
        os.environ["NOCTALIA_HM_UNIT"],
    )


if __name__ == "__main__":
    main()
