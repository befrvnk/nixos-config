# Falcon Observer

`falcon-observer` is a macOS-only Go daemon that measures CrowdStrike Falcon
activity around automatically detected local builds. It does not change projects,
build commands, build configuration, or Falcon configuration.

## Detection

The daemon polls macOS `libproc` APIs from one long-running process and uses
Mach-timebase-corrected CPU counters. It recognizes Gradle/Android, Rust, Go,
Node, CMake/Ninja/Make, Xcode/Swift, and Nix builds. Process working directories
and ancestry attribute sessions to the first project directory below the
configured project root. Full arguments and working directories are used only in
memory; persisted records contain the project basename, not command lines.

## Collection levels

While idle, the daemon keeps five minutes of native process and host metrics in
memory. A standard build session collects:

- native Falcon CPU, memory, and physical I/O counters
- `/usr/bin/powermetrics` process I/O, energy, CPU, and thermal data
- Falcon `stats --plist` snapshots at session start and end
- one `/usr/bin/sample` capture after sustained high Falcon CPU

A deep trace additionally runs `/usr/bin/fs_usage` for Falcon. Automatic deep
traces are disabled by default. An explicit `request-deep-trace` applies to the
next matching project/build-system session, even in `off` mode. Optional `daily`
mode permits at most one 60-second, 64 MiB trace per project/build-system pair
every 24 hours; `always` is reserved for foreground diagnostics.

Each completed session automatically summarizes baseline/build percentiles,
Falcon CPU and physical I/O deltas, system pressure, collector overhead, Falcon
statistics deltas, and privacy-preserving file categories/extensions. Large raw
observations, powermetrics output, Falcon stats, and filesystem paths are deleted
after successful summarization unless `--retain-raw-data=true` is explicitly
set. Stack samples are retained when created.

No Falcon diagnostic archive is generated automatically.

## Darwin service

`hosts/macbook-darwin/default.nix` installs the package and runs it as the root
LaunchDaemon `dev.befrvnk.falcon-observer`. Root is required by Apple tracing
tools and Falcon's statistics command.

Data is written under `/var/log/falcon-observer` with mode `0700`; session files
use mode `0600`. Standard collector output is limited to 128 MiB, deep traces to
64 MiB and 60 seconds, sessions to 45 minutes, retention to 14 days, and total
session storage to 2 GiB. Retention includes the active session and is enforced
periodically while collection is running.

After applying the Darwin configuration:

```bash
sudo launchctl print system/dev.befrvnk.falcon-observer
sudo tail -f /var/log/falcon-observer/daemon.log
sudo find /var/log/falcon-observer -maxdepth 2 -type f -print
```

Run a non-privileged two-snapshot detector check with:

```bash
falcon-observer scan --project-root "$HOME/projects"
```

Run only the native detector for foreground development with:

```bash
falcon-observer run \
  --collectors=false \
  --deep-trace=off \
  --project-root "$HOME/projects" \
  --output-dir "$TMPDIR/falcon-observer"
```

Request a deep trace for the next known project/build-system session without
starting a second observer:

```bash
sudo falcon-observer request-deep-trace \
  --project galaxy-android-app \
  --build-system gradle
```

Run `--deep-trace=always --retain-raw-data=true` only in a foreground diagnostic
session after temporarily stopping the LaunchDaemon; do not run two observers at
once.

Raw traces can contain usernames, repository paths, process names, and Falcon
identifiers. Keep retained traces local and share them only with the appropriate
IT or CrowdStrike support personnel.
