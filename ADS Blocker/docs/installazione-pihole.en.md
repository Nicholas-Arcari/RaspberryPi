>  [Italiano](installazione-pihole.md) |  **English**

# Installing Pi-hole with Docker and MacVLAN

## The Problem: Port 80 Conflict

OpenMediaVault (our NAS) occupies port 80 for its web interface. Pi-hole also requires port 80 for its dashboard. Additionally, Pi-hole needs port 53 (DNS), which is often occupied by `systemd-resolved`.

### What NOT to Do

**Do not install Pi-hole directly on the host** using the command found everywhere online:

```bash
# WARNING: DO NOT RUN THIS COMMAND
curl -sSL https://install.pi-hole.net | bash
```

This installs Pi-hole "bare metal" (directly on the operating system), causing:

- Port 80 conflict with OMV (nginx)
- Port 53 conflict with `systemd-resolved`
- Installation of a second `lighttpd` instance that interferes with OMV's nginx
- Dual DNS management creating confusion

If you accidentally ran this, here is what you would see - these are screenshots from the bare metal installer that should **not** be used in our setup:

![Pi-hole bare metal installer - upstream DNS selection. This installation mode should NOT be used with Docker](../img/pihole-baremetal-dns-warning.jpg)

![Pi-hole bare metal installer complete - NOT applicable to our Docker setup](../img/pihole-baremetal-install-warning.jpg)

### The Solution: Docker + MacVLAN

Instead of fighting over ports, we give Pi-hole a **dedicated IP address** on the local network using the MacVLAN driver. The Pi-hole container appears as a separate physical device with all ports free:

- Raspberry Pi (host/NAS): `192.168.0.102` -> port 80 = OMV
- Pi-hole (container): `192.168.0.250` -> port 80 = Pi-hole dashboard, port 53 = DNS

No conflicts, no port mapping.

---

## Network Configuration

| Component | IP | Role |
|---|---|---|
| Router (Gateway) | `192.168.0.1` | DHCP, routing, NAT |
| Raspberry Pi (Host) | `192.168.0.102` | NAS (OMV), Docker host |
| Pi-hole (Container) | `192.168.0.250` | DNS sinkhole |
| Subnet | `192.168.0.0/24` | Local network |
| RPi5 Physical Interface | `end0` | Ethernet (on RPi5 Bookworm it is `end0`, not `eth0`) |

> **The IP 192.168.0.250 must be outside the router's DHCP range.** If the router assigns IPs from `.100` to `.200`, then `.250` is safe. Otherwise, you risk the router assigning the same IP to another device, causing ARP conflicts.

---

## Step-by-Step Installation

### 1. Directory Structure

```bash
mkdir -p ~/pihole
cd ~/pihole
```

### 2. Docker Compose

Create the `docker-compose.yml` file:

```yaml
version: "3"

services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    hostname: pihole-nas
    domainname: lan
    networks:
      pihole_net:
        ipv4_address: 192.168.0.250
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
    environment:
      TZ: 'Europe/Rome'
      FTLCONF_LOCAL_IPV4: 192.168.0.250
      # We will set the password later via CLI to avoid leaving it in plaintext in the file
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    restart: unless-stopped

networks:
  pihole_net:
    driver: macvlan
    driver_opts:
      parent: end0  # Verify with 'ip link' - on RPi5 Bookworm it is end0, on RPi4 it is eth0
    ipam:
      config:
        - subnet: 192.168.0.0/24
          gateway: 192.168.0.1
          ip_range: 192.168.0.248/29  # Range .248-.255 reserved for Docker MacVLAN
```

**Explanation of the MacVLAN network parameters:**

- `parent: end0`: the physical interface on which Docker creates the virtual MacVLAN interface
- `ip_range: 192.168.0.248/29`: a small range of 8 IPs (`.248` to `.255`) reserved for MacVLAN containers. This prevents Docker from assigning IPs that conflict with the router's DHCP
- `cap_add: NET_ADMIN`: required because Pi-hole needs to modify the network configuration (binding to port 53, DHCP if enabled)

### 3. Startup and Password Configuration

```bash
# Start in background
docker compose up -d

# Set the dashboard password
docker exec -it pihole pihole setpassword tua_password_sicura
```

![Pi-hole dashboard just started - 79,811 domains in blocklist, 0 queries (freshly installed)](../img/pihole-dashboard.jpg)
