_:

{
  # === Firewall ===
  # Block all incoming connections by default, allow all outgoing
  # Localhost (127.0.0.1) traffic is always allowed
  networking.firewall = {
    enable = true;

    # Allowed incoming ports
    allowedTCPPorts = [
      5555 # ADB wireless debugging (traditional method)
    ];
    allowedUDPPorts = [ ];

    # Logging - view with: journalctl -k | grep "refused"
    logRefusedConnections = true; # Log refused TCP connections (default)
    logRefusedPackets = true; # Log all refused packets (verbose)
    logRefusedUnicastsOnly = true; # Only log unicast, not broadcast/multicast
  };

  # === Kernel Security Hardening ===
  # Additional security-focused sysctl settings
  # (Complements performance settings in core.nix)
  boot.kernel.sysctl = {
    # Restrict dmesg to root only
    # Kernel logs can leak sensitive information (addresses, hardware details)
    "kernel.dmesg_restrict" = 1;

    # Disable Magic SysRq key
    # Prevents physical attackers from using keyboard shortcuts for privileged ops
    # Set to 1 to allow only sync, or specific value for selective features
    "kernel.sysrq" = 0;

    # Restrict ptrace to parent processes only
    # Prevents most process debugging/injection attacks
    # 0 = no restrictions, 1 = parent only, 2 = admin only, 3 = disabled
    "kernel.yama.ptrace_scope" = 1;

    # Disable IP forwarding
    # Prevents the system from acting as a router
    # Enable only if running VMs/containers that need host networking
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;

    # Ignore ICMP redirects
    # Prevents attackers from redirecting network traffic
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;

    # Don't send ICMP redirects (we're not a router)
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;

    # Ignore source-routed packets
    # Source routing can be used to bypass firewalls
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;

    # Enable TCP SYN cookies
    # Protects against SYN flood attacks
    "net.ipv4.tcp_syncookies" = 1;

    # Log martian packets (packets with impossible addresses)
    # Useful for detecting network attacks/misconfigurations
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
  };
}
