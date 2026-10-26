# Security Hardening

This guide covers the security configuration implemented in this NixOS system, including firewall settings and kernel hardening.

## Overview

The security configuration is located in `modules/system/security.nix` and provides:

- **Firewall**: Blocks incoming connections by default
- **Kernel Hardening**: Restricts information leakage and network attack surface

## Binary-cache trust: Lantian incident

The Lantian cache and its signing key have been removed from both
`shared/caches.nix` (NixOS runtime policy) and the literal `flake.nix` cache settings.
The maintainer [reported compromised servers on 2026-10-15](https://github.com/xddxdd/nix-cachyos-kernel/issues/110#issuecomment-6189203183).
Do not restore the old endpoint/key merely because the service becomes reachable.
Any replacement trust requires explicit review.

`checks.<system>.cache-trust` checks that the flake literals match shared policy
and rejects the endpoint/key; on Linux it also checks Framework's runtime settings.
This checkpoint does not update the kernel input, change the selected kernel,
rebuild existing artifacts from source, purge store paths, or establish that any
previously downloaded artifacts are safe. Kernel/cache-origin integrity review is
separate work. The maintainer's belief that kernels were not modified is not an
independent verification of this machine's store.

The user activated this checkpoint on 2026-10-20. Inspection confirmed the old
endpoint/key are absent from `/etc/nix/nix.conf` and effective `nix config show`,
and nix-daemon is active with its restart timestamp updated. Noctalia/overview
remain active. Existing artifact/kernel integrity is still a separate question.

### Origin inventory of revoked-cache artifacts (2026-10-25)

Store-wide audit of `ValidPaths.sigs`: **23 paths** carry `lantian:` signatures, all
fetched **2026-06-25 … 2026-08-23**, i.e. before the disclosure:

- content-addressed, so Nix verified the pinned hash on download (tamper-evident):
  3× `source`, `index-x86_64-linux`, `index-x86_64-linux-small`,
  `crate-clap_complete-4.6.0.tar.gz`
- input-addressed, so the signer was trusted completely: `linux-cachyos-latest-7.1.1`
  and `-7.1.6`, `linux-cachyos-lts-6.18.42` (each with `-modules`/`-dev`),
  `linux-config-6.18.42`, 4× `55-nixos-aslr-entropy.conf`, `fedoracert`

None of the 23 appears in the active closure of `/run/current-system`; the running
kernel (`6.18.52-cachyos`) was built locally on 2026-10-22 and signed by this
machine's `hermi-signing` key. Generations 1070–1134 still reference the suspect
kernels until pruned (`nh clean all --keep 5`). To settle the remaining question for
a specific artifact, rebuild it from its hash-pinned source and compare against the
downloaded bytes: `nix build --check $(nix-store -q --deriver /nix/store/<path>)`.

### Replacement kernel cache (2026-10-25)

The CachyOS kernel now comes from Chaotic-Nyx (`chaotic-cx/nyx`) instead of
`nix-cachyos-kernel`: `https://nyx-cache.chaotic.cx/?priority=45` with key
`nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk=`, added to both
`shared/caches.nix` and the literal `flake.nix` `nixConfig` (kept in sync by
`checks.cache-trust`). Priority 45 keeps `cache.nixos.org` (40) ahead of it, so it
only fills gaps. This is a different operator from the Lantian incident; the review
was: upstream-documented project, prebuilt paths verified present before adoption,
official caches preferred by priority.

For any machine not yet updated, the live configuration keeps old trust until
activation. Use an already-built closure without cache substitution:

```sh
rebuild switch -- --option substitute false
```

After activation, inspect `/etc/nix/nix.conf` and `nix config show`: neither cache
lists nor trusted public keys should contain the old endpoint or `lantian:` key.
The agent does not run privileged activation or restart the system daemon.

## Firewall

### How It Works

The NixOS firewall uses iptables/nftables to control network traffic:

| Traffic Type | Default Behavior |
|-------------|------------------|
| **Incoming** | Blocked (except allowed ports) |
| **Outgoing** | Allowed |
| **Localhost** | Always allowed |

### Local Development

**Localhost traffic is unaffected by the firewall.** Development servers work normally:

```bash
# These all work without configuration
python -m http.server 8000      # Access via localhost:8000
npm run dev                      # Access via localhost:3000
cargo run                        # Any local server
```

### Logging

Firewall logging is enabled to track blocked connections. Shell aliases are available:

```bash
# View refused connections (alias)
firewall-log

# Live monitoring (alias, requires sudo)
firewall-log-live

# Count refused packets today
journalctl -k --since today | grep -c "refused"
```

Log prefixes:
- `refused connection:` - TCP connection attempts
- `refused packet:` - Other blocked packets

### Firewall Visibility

There is no active status-bar firewall widget in the current Noctalia V5 layout;
the old Ironbar module was removed with the retired shell. Use the journal
commands above, or the `/firewall` Claude Code command, to summarize refused
connections and resolve source IPs. The firewall remains active independently of
the shell. See `docs/noctalia-niri-overview.md`.

### Currently Open Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 5555 | TCP | ADB wireless debugging |

### Opening Additional Ports

If you need other devices on your network to connect to your laptop:

```nix
# modules/system/security.nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 5555 3000 ];  # ADB, dev server
  allowedUDPPorts = [ ];
};
```

Common ports:

| Service | Port | Protocol |
|---------|------|----------|
| ADB wireless (traditional) | 5555 | TCP |
| HTTP dev server | 3000, 8080 | TCP |

### ADB Wireless Debugging

Port 5555 is open for Android wireless debugging using the traditional method:

```bash
# 1. Connect device via USB first
adb devices

# 2. Enable TCP mode on port 5555
adb tcpip 5555

# 3. Disconnect USB, then connect over WiFi
adb connect <device-ip>:5555
```

**Note**: Android 11+ "Wireless Debugging" feature uses random ports (30000-49999) which change each time. The traditional method above uses a fixed port and is more firewall-friendly.

### Temporary Port Opening

For occasional LAN access without changing configuration:

```bash
# Open port 3000 temporarily (until reboot)
sudo iptables -I INPUT -p tcp --dport 3000 -j ACCEPT

# View current rules
sudo iptables -L INPUT -n
```

## Kernel Hardening

### Information Disclosure Protection

| Setting | Value | Purpose |
|---------|-------|---------|
| `kernel.dmesg_restrict` | 1 | Kernel logs only visible to root |
| `kernel.kptr_restrict` | 2 | Hide kernel pointers from /proc/kallsyms |
| `kernel.printk` | "3 3 3 3" | Only critical errors to console |

**Why it matters**: Kernel logs and memory addresses can reveal information useful for exploit development.

### Process Protection

| Setting | Value | Purpose |
|---------|-------|---------|
| `kernel.sysrq` | 0 | Disable Magic SysRq key |
| `kernel.yama.ptrace_scope` | 1 | Only parent can debug child processes |

**Why it matters**:
- Magic SysRq allows keyboard shortcuts that could bypass security (sync, reboot, kill processes)
- Ptrace restrictions prevent most process injection/debugging attacks

### Network Protection

| Setting | Purpose |
|---------|---------|
| `ip_forward = 0` | Prevent acting as router |
| `accept_redirects = 0` | Ignore ICMP redirects (anti-MITM) |
| `send_redirects = 0` | Don't send ICMP redirects |
| `accept_source_route = 0` | Ignore source-routed packets |
| `tcp_syncookies = 1` | SYN flood protection |
| `log_martians = 1` | Log packets with impossible addresses |

**Why it matters**: These settings harden the network stack against common attacks and information leakage.

## Existing Security Measures

This configuration also includes (configured elsewhere):

### Boot Security (`hosts/framework/default.nix`)
- **Secure Boot**: Lanzaboote with signed EFI binaries
- **LUKS Encryption**: Full disk encryption with TPM auto-unlock

### Authentication (`modules/hardware/fprintd/`)
- **Fingerprint Auth**: For sudo, login, screen lock
- **PAM Configuration**: Structured authentication rules

### Secrets Management
- **GNOME Keyring**: Encrypted credential storage
- **1Password**: Password manager with polkit integration

## What's Not Configured (Trade-offs)

Some security measures are intentionally not enabled:

| Feature | Why Not Enabled |
|---------|----------------|
| AppArmor/SELinux | Adds complexity, limited benefit for single-user laptop |
| Audit logging | Increases disk writes, mainly useful for multi-user/server |
| USB device filtering | Reduces usability with peripherals |
| Module loading restrictions | Can break hardware support |

## Checking Security Status

### Firewall

```bash
# Check if firewall is enabled
sudo iptables -L -n

# View active connections
ss -tuln
```

### Kernel Settings

```bash
# Check specific sysctl value
sysctl kernel.dmesg_restrict

# View all security-related settings
sysctl -a | grep -E "kptr|dmesg|sysrq|ptrace|forward|redirect"
```

## Troubleshooting

### Can't Connect to Dev Server from Phone/Other Device

1. Check if port is open in firewall:
   ```bash
   sudo iptables -L INPUT -n | grep <port>
   ```

2. Add port temporarily:
   ```bash
   sudo iptables -I INPUT -p tcp --dport <port> -j ACCEPT
   ```

3. Or add to configuration permanently in `modules/system/security.nix`

### Application Needs ptrace

Some debugging tools (strace, gdb on other processes) may fail with ptrace restrictions:

```bash
# Temporarily allow ptrace (for debugging session)
sudo sysctl kernel.yama.ptrace_scope=0

# Reverts on reboot
```

### Need dmesg Access as Regular User

```bash
# View kernel logs (requires sudo with dmesg_restrict=1)
sudo dmesg

# Or temporarily allow
sudo sysctl kernel.dmesg_restrict=0
```

## Security vs Usability

This configuration balances security with daily usability:

- **Secure defaults**: Firewall on, kernel hardened
- **No breaking changes**: All standard development workflows work
- **Localhost unaffected**: Dev servers work without configuration
- **Easy overrides**: Temporary sysctl or iptables changes when needed

For a personal laptop with full-disk encryption and secure boot, this provides solid protection without impacting daily use.
