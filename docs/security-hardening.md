# Security Hardening

This guide covers the security configuration implemented in this NixOS system, including firewall settings and kernel hardening.

## Overview

The security configuration is located in `modules/system/security.nix` and provides:

- **Firewall**: Blocks incoming connections by default
- **Kernel Hardening**: Restricts information leakage and network attack surface

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
