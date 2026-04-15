>  [Italiano](README.md) |  **English**

# Raspberry Pi 5 - Cyber Security Home Lab & NAS

> Complete documentation of a real-world project to turn a Raspberry Pi 5 into a multi-purpose server: NAS, SIEM, Honeypot, VPN, DNS Sinkhole and more. Written by someone who got their hands dirty, with mistakes, fixes and lessons learned in the field.

This repository gathers the entire experience - from first boot to final deployment - of a Raspberry Pi 5 configured as a home security infrastructure. This is not a collection of commands copied from StackOverflow: each section documents the **why** behind every choice, the problems encountered and the solutions adopted.

The base operating system is **OpenMediaVault 7** (Debian-based), chosen for its native NAS management. All additional services (SIEM, VPN, Honeypot, DNS Blocker) run in **Docker containers**, ensuring isolation, portability and the ability to destroy and recreate a service without touching the host system.

---

## Table of Contents

| # | Section | Description |
|---|---------|-------------|
| 1 | [First Setup](./First%20Setup/README.en.md) | OS installation, NVMe boot, initial SSH and bootloader configuration |
| 2 | [NAS (Network Attached Storage)](./NAS%20(Network%20Attached%20Storage)/README.en.md) | OpenMediaVault 7, filesystem, SMB/NFS shares, Plex Media Server |
| 3 | [Docker & Portainer](./Docker%20%26%20Portainer/README.en.md) | Docker installation on OMV, Portainer as management plane |
| 4 | [Secure your RaspberryPi](./Secure%20your%20RaspberryPi/README.en.md) | SSH hardening, Fail2ban, UFW, automatic updates, Wazuh FIM |
| 5 | [VLAN (Virtual LAN)](./VLAN%20(Virtual%20LAN)/README.en.md) | Network segmentation with IPVLAN and 802.1Q VLAN tagging |
| 6 | [VPN (Virtual Private Network)](./VPN%20(Virtual%20Private%20Network)/README.en.md) | WireGuard server with wg-easy, DDNS, Double NAT/CGNAT management |
| 7 | [ADS Blocker](./ADS%20Blocker/README.en.md) | Pi-hole on Docker with MacVLAN networking, DNS and router configuration |
| 8 | [Honeypot](./Honeypot/README.en.md) | Cowrie SSH/Telnet honeypot with Wazuh SIEM integration |
| 9 | [SOC Analyst](./SOC%20Analyst/README.en.md) | SOC analyst role and tools, with Wazuh SIEM/XDR sub-section |
| 10 | [Security Assessment & Hardening](./Security%20Assessment%20%26%20Hardening/README.en.md) | Red teaming your own lab: Nmap, Hydra, risk analysis, firewall tuning |

### Cross-cutting Resources

| Document | Content |
|---|---|
| [Network Topology](docs/topologia-rete.en.md) | Complete ASCII diagram of all components, IPs, ports and data flows |
| [Quick Reference Card](docs/quick-reference.en.md) | Addresses, ports, default credentials, emergency commands |
| [Post-installation Checklist](docs/checklist-post-installazione.en.md) | 20+ checks with commands and expected results for each component |

---

## Project Architecture

```
Raspberry Pi 5 (8GB RAM) - Raspberry Pi OS Lite 64-bit (Bookworm)
|
|-- Hardware & Boot
|   |-- Direct boot from NVMe SSD (Patriot P320 256GB PCIe Gen 3x4)
|   |-- Bootloader EEPROM updated to latest stable version
|   |-- MicroSD kept only for recovery/emergency
|   +-- Power supply: official 27W USB-C (5.1V / 5A)
|
|-- Base System: OpenMediaVault 7
|   |-- Storage management (NVMe, EXT4 filesystem)
|   |-- Network shares: SMB/CIFS + NFS
|   |-- User management and ACL permissions
|   |-- SMART disk monitoring
|   +-- Web UI on port 80 (local IP)
|
|-- Container Platform: Docker + Portainer
|   |-- Docker Engine (docker.io from Debian repo, not CE)
|   |-- Docker Root Directory on NVMe (/var/lib/docker)
|   |-- Portainer CE on port 9443 (HTTPS)
|   +-- Segmented Docker networks:
|       |-- bridge (default, for internal services)
|       |-- macvlan (Pi-hole - dedicated IP on LAN)
|       +-- ipvlan_150 (VLAN 150 for advanced isolation)
|
|-- Security Stack
|   |-- Wazuh SIEM All-in-One (Manager + Indexer + Dashboard)
|   |-- Wazuh Agents (self-monitoring + Windows/Linux hosts)
|   +-- Custom rules for Cowrie (rule ID 100010-100013)
|
|-- Network Protection
|   |-- WireGuard VPN (wg-easy, port 51820 UDP)
|   |-- Pi-hole DNS Sinkhole (79,000+ blocked domains)
|   +-- UFW Firewall (default deny incoming)
|
|-- Threat Detection
|   |-- Cowrie Honeypot (SSH port 2222, Telnet port 2223)
|   +-- Internet exposure (port forward + Ngrok fallback)
|
+-- Network Segmentation
    |-- DMZ Network -> exposed services
    |-- Internal Network -> private services
    +-- Management Network -> Portainer, Wazuh Dashboard
```

---

## Hardware Requirements

| Component | Detail | Notes |
|---|---|---|
| **Board** | Raspberry Pi 5 (8GB RAM) | 4GB is insufficient for Wazuh Indexer + Dashboard |
| **Primary storage** | NVMe SSD M.2 2280 PCIe Gen 3x4 | In my case: Patriot P320 256GB |
| **NVMe adapter** | PCIe HAT/adapter for RPi5 | Check compatibility and power requirements |
| **Secondary storage** | MicroSD 16GB+ | Only for recovery; boot is from NVMe |
| **Power supply** | Official RPi5 27W PSU (5.1V/5A) | With NVMe connected, an underpowered PSU causes instability |
| **Network** | Cat5e/Cat6 Ethernet cable | Wi-Fi not recommended for a server; MacVLAN requires Ethernet |
| **Switch** | Managed switch | Required only for 802.1Q VLAN tagging |
| **Router** | With DDNS and Port Forwarding support | In my case: TP-Link Archer C50 |

---

## Fundamental Project Rule

> **OpenMediaVault remains the primary operating system.** No additional service is installed directly on the host. Everything runs in Docker containers. This ensures that a malfunctioning service cannot corrupt the NAS, and that each component can be updated, stopped or removed independently.

---

## Recommended Reading Order

For those starting from scratch, the recommended order is:

1. **First Setup** - Install the OS, configure boot and NVMe
2. **NAS** - Configure OpenMediaVault and shares
3. **Docker & Portainer** - Install the container platform
4. **Secure your RaspberryPi** - Base hardening before exposing services
5. **VPN** - Secure remote access
6. **ADS Blocker** - DNS protection
7. **VLAN** - Advanced segmentation (optional, requires managed switch)
8. **Honeypot** - Deploy the trap
9. **SOC Analyst / Wazuh** - SIEM for centralized monitoring
10. **Security Assessment** - Test and validate the entire setup

---

## Technology Stack

| Layer | Technology | Version/Notes |
|---|---|---|
| OS | Raspberry Pi OS Lite 64-bit | Bookworm (Debian 12). Trixie not supported by OMV and Wazuh |
| NAS | OpenMediaVault 7 | Installed via official OMV-extras script |
| Container Runtime | Docker Engine (docker.io) | From Debian repository, not Docker CE |
| Container Management | Portainer CE | Web UI on HTTPS:9443 |
| SIEM/XDR | Wazuh 4.9.x | All-in-One (Manager + Indexer + Dashboard) on ARM64 |
| Log Shipper | Filebeat | Transports alerts from Manager to Indexer |
| VPN | WireGuard (wg-easy v13) | Docker container, Web UI on port 51821 |
| DNS Sinkhole | Pi-hole | Docker container, MacVLAN network |
| Honeypot | Cowrie | Docker container, SSH port 2222 |
| Firewall | UFW (Uncomplicated Firewall) | Frontend for iptables/nftables |
| Brute Force Protection | Fail2ban | Integrated with Wazuh for alerting |

---

## Automation Script

The [`scripts/setup.sh`](./scripts/setup.sh) script reproduces the entire lab from scratch. Every command is commented with an explanation of what it does and why. It supports modular execution:

```bash
# Full setup (all modules in order)
sudo ./scripts/setup.sh all

# Single module
sudo ./scripts/setup.sh hardening
sudo ./scripts/setup.sh docker
sudo ./scripts/setup.sh pihole

# Verify all services status
sudo ./scripts/setup.sh verify
```

> **Note on Wazuh:** The `wazuh` module does not automate the installation (ARM64 not officially supported, each step requires manual verification). It provides step-by-step instructions to follow.

---

## Security Notice

This project deliberately exposes a honeypot to the Internet. The documented configurations include isolation measures (firewall, network segmentation, container sandbox), but **a system exposed to the Internet requires constant maintenance**: updates, log monitoring, firewall rule review.

Do not replicate this configuration without understanding the risks. A misconfigured honeypot is an open door into your home network.

---

## License

This repository is public for educational purposes. The documented commands and configurations are specific to my network environment and may require adjustments to work correctly in yours.
