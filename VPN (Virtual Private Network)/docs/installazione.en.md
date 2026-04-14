>  [Italiano](installazione.md) |  **English**

# Installing WireGuard with Docker

## Creating the directory

```bash
mkdir -p ~/wireguard
cd ~/wireguard
```

## Docker Compose

Create the `docker-compose.yml` file:

```yaml
version: "3.8"
services:
  wg-easy:
    environment:
      # The DDNS domain pointing to your public IP
      - WG_HOST=miodominio.ddns.net

      # Password for the management Web UI
      - PASSWORD=LaMiaPasswordSegreta

      # VPN tunnel port (must match the port forwarding)
      - WG_PORT=51820

      # VPN internal subnet - each client gets a 10.8.0.x IP
      - WG_DEFAULT_ADDRESS=10.8.0.x

      # DNS used by VPN clients
      # 8.8.8.8 = Google DNS. If you have Pi-hole, use its IP
      - WG_DEFAULT_DNS=8.8.8.8

      # Subnets reachable through the VPN:
      # - 192.168.0.0/24 = home local network
      # - 10.8.0.0/24 = VPN network (for communication between VPN clients)
      # - 0.0.0.0/0 = all traffic (full tunnel)
      - WG_ALLOWED_IPS=192.168.0.0/24, 10.8.0.0/24, 0.0.0.0/0

      # Reduced MTU for mobile network compatibility
      - WG_MTU=1280

    # IMPORTANT: version 13 - see troubleshooting
    image: ghcr.io/wg-easy/wg-easy:13
    container_name: wireguard
    volumes:
      - .:/etc/wireguard
    ports:
      - "51820:51820/udp"  # VPN tunnel
      - "51821:51821/tcp"  # Management Web UI
    restart: unless-stopped
    cap_add:
      - NET_ADMIN     # Required to create network interfaces
      - SYS_MODULE    # Required to load the WireGuard kernel module
    sysctls:
      - net.ipv4.ip_forward=1           # Enables routing between interfaces
      - net.ipv4.conf.all.src_valid_mark=1  # Required for masquerading
```

## Explanation of key parameters

**`WG_ALLOWED_IPS`** - Controls which destinations are reachable through the VPN tunnel:

- `192.168.0.0/24`: only traffic to the home LAN goes through the VPN (split tunnel)
- `0.0.0.0/0`: ALL traffic goes through the VPN, including web browsing (full tunnel)
- The combination I use includes both, giving the client full access to both the LAN and the Internet through the tunnel

**`WG_MTU=1280`** - The MTU (Maximum Transmission Unit) is the maximum size of a network packet. The standard value is 1500 bytes. WireGuard adds a ~60-80 byte header to each packet (encapsulation), so the effective MTU must be reduced. With 1280:

```
[IP header: 20B] [UDP header: 8B] [WG header: ~32B] [Payload: 1280B] = ~1340B < 1500B
```

On 4G/5G mobile networks, the provider's MTU may already be reduced (1400-1420). If the WireGuard packet exceeds the provider's MTU, it gets fragmented, causing slowdowns or timeouts. 1280 is the minimum guaranteed by IPv6 and works everywhere.

## The wg-easy iptables rules (PostUp/PostDown)

When the WireGuard container starts, wg-easy automatically executes iptables rules equivalent to these (configurable with `WG_POST_UP` and `WG_POST_DOWN`):

```bash
# PostUp - executed when the wg0 interface comes up:
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# PostDown - executed on stop:
iptables -D FORWARD -i wg0 -j ACCEPT
iptables -D FORWARD -o wg0 -j ACCEPT
iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

**Rule analysis:**

| Rule | Chain | Meaning |
|---|---|---|
| `FORWARD -i wg0 -j ACCEPT` | FORWARD | Accepts packets **coming from** the VPN tunnel and destined for the LAN or Internet. Without this rule, the kernel would drop VPN client traffic |
| `FORWARD -o wg0 -j ACCEPT` | FORWARD | Accepts packets **directed to** the VPN tunnel (responses from LAN/Internet to VPN clients) |
| `POSTROUTING -o eth0 -j MASQUERADE` | NAT | **Critical**: performs Source NAT (SNAT) on packets leaving the physical interface. When a VPN client (10.8.0.2) accesses a device on the LAN (192.168.0.50), the source IP is rewritten with the Raspberry Pi's IP (192.168.0.102). Without this rule, the destination device would receive a packet with source 10.8.0.2 and would not know how to respond (it has no route to the 10.8.0.0/24 subnet) |

**`MASQUERADE` vs `SNAT`:** On an interface with a dynamic IP (as in our case with DHCP), `MASQUERADE` is used because it determines the source IP automatically on each packet. On an interface with a static IP, `SNAT --to-source <IP>` would be slightly more efficient because it does not need to perform the IP lookup on each packet.

The `sysctl` `net.ipv4.ip_forward=1` in the Docker Compose enables routing between interfaces in the container's namespace - without it, the kernel would drop any packet not destined for itself.

## Startup

```bash
docker compose up -d
```

Web UI reachable at: `http://192.168.0.102:51821`

## Verifying the tunnel status: `wg show`

After connecting a client, enter the container to check the status:

```bash
docker exec -it wireguard wg show
```

Example output with two connected clients:

```
interface: wg0
  public key: sRvY7mZB3K+x4QJn0dR1zE8bGPaj5N9vqKsMwoXf+Ew=
  private key: (hidden)
  listening port: 51820

peer: gN65BkIKwT6rH0mJ2dPVzxR1aLbcOq5Nf3uYpWvX8Ds=
  endpoint: 82.XX.XX.XX:43721
  allowed ips: 10.8.0.2/32
  latest handshake: 47 seconds ago
  transfer: 2.47 MiB received, 14.82 MiB sent

peer: 7Rp2kLQmVnB9oT1jX5yDfUwS8hAcEi6Zx0GqNpMrJ4k=
  endpoint: 151.XX.XX.XX:51820
  allowed ips: 10.8.0.3/32
  latest handshake: 3 minutes, 12 seconds ago
  transfer: 892.31 KiB received, 4.21 MiB sent
```

**Reading the fields:**

| Field | Meaning | What to look for |
|---|---|---|
| `public key` (interface) | Server's public key | Must match the one in the client configuration file |
| `listening port` | UDP port WireGuard is listening on | Must match the router's port forwarding (51820) |
| `endpoint` | Peer's current IP:port | Updates automatically as the client roams |
| `allowed ips` | Authorized subnets for that peer | `10.8.0.2/32` = only its VPN IP (server-side split tunnel) |
| `latest handshake` | Time since the last completed handshake | If it exceeds 5 minutes, the session has expired. If it says `(none)`, the client has never connected |
| `transfer` | Bytes exchanged (received = from client, sent = to client) | Extreme asymmetry (high sent, low received) is normal: the client browses and the server forwards responses |

> **Quick diagnostics:** If `latest handshake` shows `(none)` and the client appears connected, the problem is almost always the port forwarding: the UDP packet is not reaching the server. Verify that port 51820/UDP is open on the router and that UFW is not blocking it (`sudo ufw allow 51820/udp`)
