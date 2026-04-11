>  [Italiano](kernel-hardening.md) |  **English**

# Kernel Hardening with sysctl and Automatic Updates

## sysctl Hardening

Beyond the firewall, the Linux kernel exposes configurable parameters via `sysctl` that harden the network stack and memory. These parameters are particularly important for a system exposed to the Internet (even indirectly through a honeypot).

### Configuration

Create the file `/etc/sysctl.d/99-hardening.conf`:

```bash
sudo nano /etc/sysctl.d/99-hardening.conf
```

```ini
# === NETWORK STACK HARDENING ===

# Enable SYN flood protection (SYN cookies)
# When the SYN queue is full, the kernel generates a cryptographic SYN cookie
# instead of allocating memory - prevents DoS from SYN flood
net.ipv4.tcp_syncookies = 1

# Disable source routing
# Source routing allows the sender to specify the path packets take
# through the network - used in routing manipulation attacks
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Ignore ICMP redirects
# ICMP redirects tell the host to use a different gateway
# An attacker can use them to redirect traffic (MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Disable sending of ICMP redirects
# A server should never act as a router - do not send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Enable Reverse Path Filtering (anti-spoofing)
# The kernel verifies that the source IP of an incoming packet is
# reachable from the interface it arrived on - blocks packets with
# spoofed source IPs
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore broadcast pings (Smurf attack prevention)
# An attacker sends a ping to the network broadcast address with a
# spoofed source IP (the victim) - all hosts respond to the victim
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log "martian" packets (impossible source IP)
# Useful for debugging and detecting spoofing attempts
net.ipv4.conf.all.log_martians = 1

# === MEMORY PROTECTION ===

# ASLR (Address Space Layout Randomization) - maximum level
# Randomizes the positions of stack, heap, mmap, and libraries in memory
# Makes exploiting buffer overflow vulnerabilities much harder
# 0 = disabled, 1 = stack/mmap, 2 = stack/mmap/heap (maximum)
kernel.randomize_va_space = 2

# Protect symlinks and hardlinks in world-writable directories (/tmp)
# Prevents symlink race condition attacks (privilege escalation)
fs.protected_symlinks = 1
fs.protected_hardlinks = 1

# Restrict dmesg access to users with CAP_SYSLOG
# dmesg can reveal kernel memory information (useful for exploits)
kernel.dmesg_restrict = 1

# Disable the ability to load unsigned kernel modules
# Prevents loading rootkits as kernel modules
# NOTE: enable only if all necessary modules are already loaded
# kernel.modules_disabled = 1   # <-- COMMENTED: WireGuard may need to load modules

# Restrict the use of perf (performance counters) - exploitable for side-channel attacks
kernel.perf_event_paranoid = 3
```

### Applying the Changes

```bash
sudo sysctl --system
```

### Verification

```bash
# Check that the parameters are active
sysctl net.ipv4.tcp_syncookies
# net.ipv4.tcp_syncookies = 1

sysctl kernel.randomize_va_space
# kernel.randomize_va_space = 2
```

> **Note on `kernel.modules_disabled`:** If you enable it (value 1), no kernel module can be loaded until the next reboot. This blocks kernel-mode rootkits, but also prevents WireGuard from loading its module if it is not already loaded. Enable only after verifying that all services are working correctly.

---

## Automatic Updates

Vulnerabilities are discovered daily. An unpatched system is an easy target. `unattended-upgrades` automatically installs security patches without manual intervention.

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure unattended-upgrades
```

The `dpkg-reconfigure` command displays an interactive screen - select **Yes** to enable automatic updates.

**What gets automatically updated:**

- Debian security patches (`*-security` repository)
- **NOT** feature updates or new major versions

This is the correct behavior for a server: you want security fixes, you don't want an update breaking OMV or Docker without notice.
