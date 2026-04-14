>  [Italiano](README.md) |  **English**

# VLAN and IPVLAN - Advanced Network Segmentation with Docker

This guide documents the configuration of Docker containers on a Raspberry Pi using the **IPVLAN** network driver in L2 mode on a **dedicated VLAN (802.1Q)**. It includes the theory needed to understand what is being done and the problems I encountered in practice.

---

## Table of Contents

| Section | Content |
|---|---|
| [VLAN Theory](docs/teoria-vlan.en.md) | Why segment the network, VLAN tagging (IEEE 802.1Q), Access vs Trunk ports |
| [Docker Network Drivers](docs/driver-docker.en.md) | Comparison between Bridge, MacVLAN and IPVLAN (L2 mode) with comparison table |
| [Kernel IPVLAN](docs/kernel-ipvlan.en.md) | Deep dive: packet flow at the kernel level (egress and ingress), ARP in IPVLAN vs MacVLAN |
| [Installation](docs/installazione.en.md) | Step-by-step guide: VLAN interface, Docker IPVLAN network, connectivity test, tcpdump, Pi-hole deploy, bridge migration |
| [Troubleshooting](docs/troubleshooting.en.md) | Known limitations: host-container communication, unreachable container, unmanaged switch |

---

Next step: [VPN (Virtual Private Network)](../VPN%20(Virtual%20Private%20Network)/) - secure remote access to the LAN.
