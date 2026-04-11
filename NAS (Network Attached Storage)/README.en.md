>  [Italiano](README.md) |  **English**

# NAS - Network Attached Storage with OpenMediaVault 7

This section documents the transformation of a Raspberry Pi 5 into a full-fledged NAS using OpenMediaVault 7, from NVMe disk preparation to network share configuration accessible from Windows, macOS, and Linux.

---

## Theory: What is a NAS and Why OMV

A NAS (Network Attached Storage) is a network-attached device dedicated to file sharing. Unlike a simple shared USB hard drive, a NAS offers:

- **Standard network protocols** (SMB for Windows, NFS for Linux/macOS)
- **User and permission management** (who can read, who can write)
- **Disk health monitoring** (SMART)
- **Web interface** for configuration

**OpenMediaVault (OMV)** is an open-source NAS distribution based on Debian. Version 7 (based on Bookworm) is compatible with ARM64 and installs on top of an existing Raspberry Pi OS Lite without overwriting it. OMV effectively becomes a "management layer" that controls network services, storage, and permissions through a web UI on port 80.

---

## Table of Contents

| # | Section | Description |
|---|---------|-------------|
| 1 | [NVMe Preparation](docs/preparazione-nvme.en.md) | Disk detection, kernel verification, PCIe, common causes of detection failure, disk wiping |
| 2 | [EXT4 Filesystem](docs/filesystem-ext4.en.md) | GPT partitioning, EXT4 formatting, deep dive into journaling modes, persistent mount with fstab |
| 3 | [OMV Installation](docs/installazione-omv.en.md) | Prerequisites, installation via official script, web UI access |
| 4 | [OMV Configuration](docs/configurazione-omv.en.md) | Disk management, filesystem, shared folders, SMB/CIFS, NFS, testing from Windows and Linux |
| 5 | [Plex Media Server](docs/plex.en.md) | Plex installation, verification and access, maintenance tips |
| 6 | [Alternatives and Comparisons](docs/alternative.en.md) | RPi as NAS (when yes/no), RPi vs Synology/QNAP, alternative SBCs, NAS software (OMV vs TrueNAS vs CasaOS vs Unraid), CasaOS installation |

---

Next step: [Docker & Portainer](../Docker%20%26%20Portainer/README.en.md) - install the container platform for all additional services.
