>  [Italiano](alternative.md) |  **English**

# Does a Raspberry Pi Make Sense as a NAS? When Yes and When No

This is the first question to ask yourself. The honest answer: **it depends on the workload**.

## When a Raspberry Pi as a NAS makes sense

- **Educational home lab** (our case): you want to learn Linux, Docker, SIEM, networking. The Pi costs 80-100 EUR and is sufficient
- **Lightweight personal archive**: photos, documents, periodic backups. 1-3 simultaneous users
- **Single-use media server**: Plex/Jellyfin for 1-2 simultaneous streams (the Pi5 handles hardware H.264 transcoding)
- **Limited budget**: a 2-bay Synology NAS starts at 300+ EUR without disks

## When it does NOT make sense

- **More than 5 simultaneous users**: the Pi's USB3/PCIe bus saturates (~500 MB/s theoretical, ~400 MB/s real)
- **RAID/Data redundancy**: the Pi has a single PCIe slot - you cannot do RAID without a USB hub (which adds a bottleneck)
- **Heavy 24/7 I/O workloads**: databases, virtual machines, surveillance with 10+ cameras
- **Enterprise reliability**: the Pi has no ECC RAM, no redundant power supply, a power failure can corrupt the filesystem

## Comparison: Raspberry Pi vs Dedicated NAS vs Mini-PC

| | RPi 5 (8GB) | Synology DS224+ | QNAP TS-233 | Mini-PC x86 (N100) |
|---|---|---|---|---|
| **Price (unit only)** | ~80 EUR | ~350 EUR | ~250 EUR | ~150 EUR |
| **CPU** | Cortex-A76 4-core | Celeron J4125 4-core | Cortex-A55 4-core | Intel N100 4-core |
| **RAM** | 8GB LPDDR4X | 2GB DDR4 (exp. 6GB) | 2GB DDR4 | 8-16GB DDR5 |
| **Disk slots** | 1x PCIe + 1x microSD | 2x SATA 3.5" | 2x SATA 3.5" | 1x NVMe + 2x SATA |
| **RAID** | No (single disk) | RAID 1 (mirror) | RAID 1 | RAID 1 (with 2 SATA) |
| **Network** | 1x Gigabit | 1x Gigabit | 1x 2.5GbE | 1-2x 2.5GbE |
| **Power consumption** | 5-8W | 15-20W | 10-15W | 15-25W |
| **Docker** | Yes (ARM64) | Yes (x86) | Yes (ARM64) | Yes (x86) |
| **Wazuh** | Yes (manual) | Difficult (limited resources) | No (2GB RAM) | **Yes** (standard setup) |
| **NAS software** | OMV, CasaOS | Synology DSM (proprietary) | QNAP QTS (proprietary) | OMV, TrueNAS, Unraid |

> **My conclusion:** For the specific scope of this lab project (NAS + SIEM + Honeypot + VPN), the Raspberry Pi 5 8GB is at its **limit**. If I were to redo the project with a slightly higher budget, I would go with an x86 mini-PC with an N100 (or N200): same price range as the Pi + power supply + case + NVMe, but with x86 architecture natively supported by everything (Wazuh, Splunk, standard Docker images), more expandable RAM, and 2.5GbE.

## Alternatives to the Raspberry Pi: Other SBCs (Single Board Computers)

| SBC | CPU | RAM | Storage | Price | Pros | Cons |
|---|---|---|---|---|---|---|
| **Orange Pi 5 Plus** | RK3588 (8-core, 4x A76 + 4x A55) | 8-32GB | 2x NVMe M.2 | ~120 EUR | Two NVMe slots (software RAID possible), 2x 2.5GbE | Less mature software, smaller community |
| **ODROID H4 Plus** | Intel N97 (x86, 4-core) | 32GB DDR5 | 2x NVMe + 2x SATA | ~150 EUR | **Native x86**, perfect Docker/Wazuh support | Not an ARM SBC (more similar to a mini-PC) |
| **Rock Pi 5B** | RK3588 | 8-16GB | 1x NVMe + eMMC | ~100 EUR | Good processing power, NPU for AI | Linux support still maturing |
| **Banana Pi BPI-R4** | MediaTek MT7988A | 4GB | eMMC + microSD | ~100 EUR | 2x 2.5GbE + Wi-Fi 7, designed as a router | Limited RAM for SIEM |

> **Question to ask yourself:** "Do I need ARM or x86?" If the project is purely educational on ARM and you want to tackle compatibility challenges, the Pi is perfect. If you want everything to work on the first try, an ODROID H4 (x86) eliminates 90% of the issues documented in this repo.

## Alternatives to OpenMediaVault: Other NAS Software

| Software | Base | Filesystem | License | RPi 5 | Unique feature |
|---|---|---|---|---|---|
| **OpenMediaVault 7** | Debian 12 | EXT4, Btrfs, XFS | GPLv3 | **Yes** | Plugin ecosystem, native Debian integration |
| **TrueNAS Scale** | Debian 12 | **OpenZFS** | BSD | No (x86 only) | ZFS: snapshots, dedup, self-healing, RAIDZ |
| **TrueNAS Core** | FreeBSD | OpenZFS | BSD | No (x86 only) | FreeBSD stability, bhyve VMs |
| **CasaOS** | Any Linux | Any | Apache 2.0 | **Yes** | Modern UI, one-click app store, lightweight |
| **Unraid** | Slackware | XFS + Btrfs (cache) | Proprietary ($59+) | No (x86 only) | Array parity without traditional RAID, Docker/VM |

### CasaOS: A lightweight alternative for those who want simplicity

If your goal is just a NAS with Docker and a nice interface, CasaOS is much lighter than OMV:

```bash
# CasaOS installation (one liner)
curl -fsSL https://get.casaos.io | sudo bash

# After installation, access at http://<IP>:80
# Built-in app store: Pi-hole, Portainer, Jellyfin, Nextcloud in one click
```

| | OMV 7 | CasaOS |
|---|---|---|
| **Setup complexity** | Medium (script + configuration) | Low (one command) |
| **Disk management** | Full (RAID, SMART, filesystem) | Basic (mount and share) |
| **Plugins** | Broad ecosystem | Docker-based app store |
| **Resources** | ~200MB RAM | ~80MB RAM |
| **Docker conflicts** | Possible (port 80, systemd) | None (Docker-native) |
| **For our project** | **Chosen** (advanced disk management) | Valid alternative if SMART/RAID is not needed |

> **Why I chose OMV over CasaOS:** OMV offers enterprise-level disk management (SMART monitoring, I/O scheduler, filesystem tuning, granular ACLs). CasaOS is more user-friendly but lacks these features. For a security lab where the disk works heavily (SIEM logs, OpenSearch indices), the control offered by OMV is necessary.
