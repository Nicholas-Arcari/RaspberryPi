>  [Italiano](vpn-e-container-recovery.md) |  **English**

# Runbook 04 - VPN and container recovery

> **When to use this runbook:** you can no longer connect to the WireGuard VPN from outside the house, a container died or is in a restart loop, or Docker will not start at all. Two related families of problems: the VPN runs in a container, and the containers run on Docker.

---

## Part A - The WireGuard VPN won't connect from outside

WireGuard is silent by design: if something along the path is wrong, the client gives no clear error, it simply "does not complete the handshake". You diagnose from the bottom up, following the packet from the outside to the container.

```
   Client (4G) -> DDNS DNS -> public IP -> CGNAT? -> Router -> port fwd -> Pi -> wg container
        [1]         [2]          [3]         [4]       [5]        [6]        [7]     [8]
```

### A.1 Does the DDNS name resolve? [2]

```bash
dig +short miodominio.ddns.net
curl -s https://api.ipify.org ; echo    # real public IP
# The two values must match. If not -> DDNS problem: go to Runbook 02, Part D
```

### A.2 Is the VPN port reachable from outside? [3][5][6]

WireGuard uses **UDP/51820**. Testing UDP from outside is awkward (no TCP handshake), but it can be done:

```bash
# On the Pi: is WireGuard really listening on the right UDP?
sudo ss -ulnp | grep 51820
# Expected: 0.0.0.0:51820

# From outside (e.g. from a VPS or the phone on 4G with an app), verify UDP 51820.
# Alternatively, an indirect check: is the honeypot on 2222/TCP reachable from outside?
#   If even the honeypot's TCP port forward doesn't work, the problem is router/CGNAT (A.3),
#   not WireGuard.
```

### A.3 CGNAT: the most likely and most misunderstood cause [4]

The uplink is an FWA antenna (Comeser) behind **CGNAT**: the "public" IP you see on the router is actually shared and not routable from outside towards you. Typical symptom: **the DDNS is perfect, the port forward is configured, but nothing gets in from outside.**

```bash
# How to recognize CGNAT: the router's WAN IP is in a CGNAT range (100.64.0.0/10)
#   or is different from the IP seen by api.ipify.org.
# On the router, look at the WAN IP and compare it:
curl -s https://api.ipify.org ; echo
# If the router's WAN IP (e.g. 100.x.y.z) != ipify IP -> you are behind CGNAT
```

If you are behind CGNAT, port forwarding **cannot work** and no WireGuard configuration bypasses it. The ways out:

| Solution | How | Note |
|---|---|---|
| Outbound tunnel | Cloudflare Tunnel / Tailscale / Ngrok | No inbound port needed; the Pi opens the connection outward |
| Public IP from the provider | Ask Comeser for a static public IPv4 | Sometimes paid; fixes it at the root |
| IPv6 | If the provider offers end-to-end public IPv6 | WireGuard over IPv6 bypasses IPv4 CGNAT |

See [VPN / rete-dmz](../../VPN%20(Virtual%20Private%20Network)/docs/rete-dmz.en.md) for the network context.

### A.4 The handshake does not complete [7][8]

If the packet reaches the container but the tunnel does not come up, it is a key or a time problem.

```bash
# Peer status: the last handshake and traffic
docker exec wireguard wg show
# "latest handshake: 30 seconds ago" -> tunnel alive
# "latest handshake" absent and transfer 0 -> the peer never completes:
#    - public/private key mismatch (peer reconfigured)
#    - Pi clock off (WireGuard is time-sensitive for the nonces)
#    - wrong AllowedIPs on the client

# Check the clock (a skewed time breaks crypto and logs)
timedatectl status | grep -E "System clock|synchronized"
# Expected: "System clock synchronized: yes"
```

### A.5 The tunnel comes up but I can't reach the LAN

Handshake ok, but you can't ping `192.168.0.102`: it is routing/firewall, not VPN.

```bash
# On the Pi: is IP forwarding on? (needed to route the VPN traffic to the LAN)
sysctl net.ipv4.ip_forward
# Expected: net.ipv4.ip_forward = 1

# Is UFW blocking the forward from the VPN subnet (10.8.0.0/24) to the LAN?
sudo ufw status verbose | grep -i 10.8
```

---

## Part B - Docker won't start

If the Docker daemon is down, **all** the containers (Portainer, Pi-hole, WireGuard, Cowrie) are down together. It is a high-impact fault.

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker -b --no-pager | tail -40
```

Typical causes and fixes:

| Symptom in the logs | Cause | Fix |
|---|---|---|
| `failed to start daemon ... no space` | Full disk | [Runbook 09](risorse-e-credenziali.en.md), then `systemctl start docker` |
| `error initializing ... /var/lib/docker` | Corrupted Docker storage (often after an unclean shutdown) | See below |
| `dockerd ... permission` after an update | Malformed daemon.json | `sudo dockerd --validate` / fix the JSON |

```bash
# Check the daemon config (a malformed JSON prevents startup)
sudo cat /etc/docker/daemon.json | python3 -m json.tool

# Docker Root is on NVMe (/var/lib/docker): check it is mounted and healthy
df -h /var/lib/docker
# If after an unclean shutdown the storage is corrupted, you may have to recover
# from the volume backups (Runbook 08). The services' data lives in the mounted
# volumes, not in the image: this is why the compose + volumes are enough to rebuild.
```

---

## Part C - A container is dead or in a crash loop

Docker is up, but a single service is not. Diagnosis starts from the state and the exit code.

```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# "Restarting (1)" -> crash loop.  "Exited (137)" -> killed by OOM

# The truth is always in the container logs
docker logs <name> --tail 80
```

Exit code as a diagnosis (see also [Runbook 00](triage-diagnostica.en.md)):

| Exit | Meaning | Direction |
|---|---|---|
| `137` | SIGKILL, almost always **OOM** | [Runbook 09](risorse-e-credenziali.en.md): RAM/limits |
| `1`/`2` | App error / wrong config | Read the logs, fix the compose/env |
| `139` | Segfault | Wrong image/arch (ARM64!) or a bug |

Clean recreation (data survives in the volumes):

```bash
# From the service's compose folder
cd /path/to/compose/<service>
docker compose down
docker compose up -d --force-recreate

# If you suspect a corrupted or wrong image (e.g. non-ARM64):
docker compose pull        # re-download the image
docker image inspect <img> --format '{{.Architecture}}'   # must be arm64/aarch64
```

> **Why "recreate" is safe.** In the lab's design, each service keeps its data in **mounted Docker volumes**, not inside the container. Destroying and recreating the container does not touch the data: it is precisely the property that makes containers recoverable in one command. The only things to safeguard are the volumes and the compose/env files -> [Runbook 08](backup-e-disaster-recovery.en.md).

---

## Recovery verification

```bash
# VPN
docker exec wireguard wg show | grep -A1 peer     # recent handshake on a connected client
# Containers
docker ps --format "table {{.Names}}\t{{.Status}}"  # all "Up"
# Docker
sudo systemctl is-active docker                    # active
```

---

## Prevention

- **CGNAT:** decide the remote-access strategy in advance (outbound tunnel vs public IP). Do not discover CGNAT during an emergency, while you are away from home and need to get in.
- **Restart policy:** set `restart: unless-stopped` in the compose files so the containers come back on their own after a reboot; but a persistent crash loop must be investigated, not ignored.
- **Resource limits:** put `mem_limit` on the non-critical containers so it is not Wazuh's indexer that dies from OOM when Cowrie goes wild.
- **Clock:** keep `systemd-timesyncd` active; a skewed time breaks WireGuard, the certificates and the logs all at once.

---

## Links

- OOM / full disk behind an exit 137 -> [Runbook 09: resources and credentials](risorse-e-credenziali.en.md)
- The DDNS name does not resolve -> [Runbook 02: DNS / Pi-hole](dns-pihole-recovery.en.md)
- Rebuilding the volumes from backup -> [Runbook 08: backup and disaster recovery](backup-e-disaster-recovery.en.md)
- WireGuard and DMZ in detail -> [VPN / teoria-wireguard](../../VPN%20(Virtual%20Private%20Network)/docs/teoria-wireguard.en.md), [VPN / troubleshooting](../../VPN%20(Virtual%20Private%20Network)/docs/troubleshooting.en.md)
