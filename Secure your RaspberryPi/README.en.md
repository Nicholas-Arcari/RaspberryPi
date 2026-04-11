>  [Italiano](README.md) |  **English**

# Raspberry Pi Hardening - Security Guide

A Raspberry Pi exposed on a network (even just LAN) with active services is a target. This guide covers the fundamental security measures I applied to my system, explaining not only the "how" but the "why" behind each configuration.

The philosophy is **defense in depth**: no single measure is sufficient, but the combination of multiple layers makes an attack significantly harder.

---

## Documentation Index

| Document | Content |
|---|---|
| [Deep Dive: SSH Protocol](docs/protocollo-ssh.en.md) | 5 connection phases, Diffie-Hellman KEX on Curve25519, host keys vs user keys, fingerprint, known_hosts (TOFU), authorized_keys, challenge-response |
| [SSH Hardening](docs/hardening-ssh.en.md) | sshd_config configuration with justification for each directive, Ed25519 public key setup, OMV integration |
| [Fail2ban](docs/fail2ban.en.md) | Brute force protection: filter, jail, action, custom configuration |
| [UFW Firewall + netfilter](docs/firewall-ufw.en.md) | 5 netfilter hook points, 4 iptables tables, connection tracking (conntrack), UFW to iptables mapping, project rules |
| [Kernel Hardening + Updates](docs/kernel-hardening.en.md) | Sysctl: SYN cookies, ICMP redirect, rp_filter, ASLR, symlink protection. Unattended upgrades |
| [Wazuh FIM Integration](docs/integrazione-wazuh.en.md) | File Integrity Monitoring verification, test alerts, force rescan |

---

## Summary: defense in depth

| Layer | Protection | What it detects/blocks |
|---|---|---|
| **SSH** | Public key, no root, no password | Brute force, unauthorized access |
| **Fail2ban** | Automatic IP banning | Bots and automated scanners |
| **UFW** | Firewall with deny-by-default policy | Port scans, unauthorized access |
| **sysctl** | Kernel hardening (network + memory) | SYN flood, IP spoofing, buffer overflow |
| **Unattended Upgrades** | Automatic patching | Known vulnerabilities (CVE) |
| **Wazuh FIM** | Integrity monitoring | Unauthorized modifications to system files |

Wazuh will start generating alerts for:

- Failed SSH attempts (rule.id: 5710, 5712)
- Fail2ban bans (rule.id: 87101-87105)
- Modifications to monitored files (rule.id: 550-554)
- Privilege escalation (`sudo` usage - rule.id: 5401-5405)
