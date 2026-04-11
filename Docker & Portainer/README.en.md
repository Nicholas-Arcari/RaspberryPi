>  [Italiano](README.md) |  **English**

# Docker & Portainer on Raspberry Pi 5 with OpenMediaVault

This guide documents the installation of Docker and Portainer on a Raspberry Pi 5 with OpenMediaVault, covering the pitfalls specific to this combination (OMV + Debian + ARM64) and best practices for a stable environment.

---

## Why Docker on a NAS

OpenMediaVault manages the NAS. If we installed Wazuh, Pi-hole, Cowrie, and WireGuard directly on the host, their services (nginx, PHP, network ports) would conflict with those of OMV. Docker solves this problem at the root: each service lives in its own isolated container, with its own network stack and filesystem, without interfering with the host system.

Containers leverage three Linux kernel primitives: **Namespaces** (isolate resource visibility), **Cgroups** (limit CPU, RAM, and I/O consumption), and **OverlayFS** (copy-on-write layered filesystem). Unlike Virtual Machines, containers share the host kernel without emulating hardware, making them lightweight and fast.

---

## Table of Contents

| Section | Content |
|---|---|
| [Kernel Internals](docs/kernel-internals.en.md) | Theory: `clone()` syscall, namespace flags, PID namespace, cgroups v2, controllers, practical verification |
| [Docker Installation](docs/installazione.en.md) | Initial check, removing docker-ce, why `docker.io`, installation, user permissions |
| [Portainer](docs/portainer.en.md) | Persistent volume, container startup, web UI access, updating, version pinning |
| [Container Security](docs/sicurezza-container.en.md) | overlay2, seccomp, AppArmor, Linux capabilities, defense-in-depth summary |
| [Alternatives](docs/alternative.en.md) | Docker vs Podman vs LXC, Portainer vs Yacht vs Dockge, Podman installation |
| [Maintenance](docs/manutenzione.en.md) | Useful commands, analyst questions (compromise, data persistence, reboot, disk space), what to avoid |

---

Next step: [Secure your RaspberryPi](../Secure%20your%20RaspberryPi/) - system hardening before exposing services.
