"""Temporary one-way Noctalia -> prebuilt Home Manager theme adapter.

Requests are atomic files consumed by a systemd PathExists/finite-worker pair.
Exec readiness lets Home Manager unit switching finish before this worker waits
for HM activation. No persistent poller, Nix rebuild, Noctalia restart, or reverse
mode write is used.
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


def process_requests(runtime, state_path, noctalia, hm_unit, *, activation_lock=None):
    activation_lock = activation_lock or state_path.parent / "theme-activation.lock"
    while read_json(runtime / "request.json"):
        wait_for_activation(hm_unit)
        # The same lock is held by ordinary HM activation hooks, so even a
        # rebuild beginning after our initial wait cannot race linkGeneration.
        # Retain the old runtime lock too while older generations may coexist.
        # Both new callers take the persistent lock first, avoiding lock inversion.
        with locked(activation_lock), locked(runtime / "activation.lock"):
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
            if changed or forced or retry_refresh or pending.get("refresh", False):
                # Initial removal of an HM-managed dconf key resets it once.
                # Let Noctalia reassert its own preference through its native
                # template pipeline; this neither changes mode nor fires palette hooks.
                reply = run([noctalia, "msg", "templates-apply"], capture_output=True,
                            text=True, timeout=10).stdout.strip()
                if reply != "ok":
                    raise RuntimeError(f"Native app-theme refresh failed: {reply}")
                atomic_json(state_path, {**applied, "refresh_pending": False})
                print(f"Refreshed {mode} app-theme clients", flush=True)

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
    runtime_root = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    runtime = runtime_root / "noctalia-theme"
    state_root = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    state_path = state_root / "noctalia" / "theme-bridge.json"
    if args.action == "request":
        # Ordinary HM activation may have replaced themed files with the base.
        # Invalidate only our applied-generation cache, even before login, so the
        # session-start request reapplies the mode instead of trusting stale state.
        if args.force:
            state_path.unlink(missing_ok=True)
        if not runtime_root.is_dir():
            print("User runtime directory unavailable; deferring theme request until session startup")
            return
        request(runtime, force=args.force, refresh=args.refresh)
        return
    process_requests(
        runtime, state_path,
        os.environ["NOCTALIA_COMMAND"],
        os.environ["NOCTALIA_HM_UNIT"],
        activation_lock=Path(os.environ.get("NOCTALIA_ACTIVATION_LOCK")
                             or str(state_root / "noctalia" / "theme-activation.lock")),
    )


if __name__ == "__main__":
    main()
