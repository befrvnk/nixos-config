# Falcon Observer

`falcon-observer` is a macOS-only Go daemon that measures CrowdStrike Falcon
activity around automatically detected Gradle work. It does not change projects,
build commands, Gradle configuration, or Falcon configuration.

## Detection

The daemon polls macOS `libproc` APIs from one long-running process. It reads
arguments only for Java, Gradle, and Kotlin candidates and recognizes Gradle
clients, daemons, Kotlin tools, `aapt2`, and descendant native build tools. A
Gradle client triggers immediately; daemon-only activity must exceed the
configured CPU threshold. Idle Gradle daemons do not trigger collection.

## Collection

While idle, the daemon keeps five minutes of process and host CPU/memory metrics
in memory. During a Gradle session it writes the pre-roll and starts bounded:

- `/usr/bin/fs_usage` for `com.crowdstrike.falcon.Agent`
- `/usr/bin/powermetrics` for process I/O, energy, disk, CPU, and thermal data
- Falcon `stats --plist` snapshots at session start and end
- one `/usr/bin/sample` capture if Falcon has sustained high CPU

No Falcon diagnostic archive is generated automatically. Full process arguments
are used only for in-memory classification and are not persisted.

## Darwin service

`hosts/macbook-darwin/default.nix` installs the package and runs it as the root
LaunchDaemon `dev.befrvnk.falcon-observer`. Root is required by the Apple tracing
tools and by Falcon's own statistics command.

Data is written under `/var/log/falcon-observer` with mode `0700`; session files
use mode `0600`. Each detailed collector is limited to 512 MiB, sessions to 45
minutes, retention to 14 days, and total session storage to 5 GiB.

After applying the Darwin configuration:

```bash
sudo launchctl print system/dev.befrvnk.falcon-observer
sudo tail -f /var/log/falcon-observer/daemon.log
sudo find /var/log/falcon-observer -maxdepth 2 -type f -print
```

Run a non-privileged two-snapshot detector check with:

```bash
falcon-observer scan
```

Disable detailed collectors for foreground detector development with:

```bash
falcon-observer run --collectors=false --output-dir "$TMPDIR/falcon-observer"
```

Raw traces can contain usernames, repository paths, process names, and Falcon
identifiers. Keep them local and share them only with the appropriate IT or
CrowdStrike support personnel.
