>  [Italiano](alternative.md) |  **English**

# Why WireGuard and not the alternatives: a critical analysis

## WireGuard vs Tailscale vs OpenVPN vs ZeroTier vs NordVPN

| Aspect | WireGuard | Tailscale | OpenVPN | ZeroTier | NordVPN/Surfshark |
|---|---|---|---|---|---|
| **Architecture** | Point-to-point, self-hosted | Mesh P2P, cloud-coordinated | Client-server, self-hosted | Mesh P2P, cloud-coordinated | Client-server, provider-hosted |
| **OSI Layer** | Layer 3 (IP tunnel) | Layer 3 (WireGuard underneath) | Layer 2 or 3 | Layer 2 (virtual Ethernet) | Layer 3 |
| **Port forwarding required** | **Yes** (51820/UDP) | **No** (automatic NAT traversal) | **Yes** (1194/UDP or 443/TCP) | **No** (NAT traversal) | **No** (provider's server) |
| **Works behind CGNAT** | Only with Ngrok/tunnel | **Yes** (native) | Only with TCP on 443 | **Yes** (native) | **Yes** (external server) |
| **Infrastructure control** | Total (self-hosted) | Partial (Tailscale coordination server) | Total | Partial (ZeroTier root servers) | None (provider) |
| **Encryption** | ChaCha20-Poly1305 (fixed) | WireGuard (under the hood) | Configurable (AES-256, etc.) | ChaCha20 or AES-256 | AES-256 (provider-managed) |
| **Performance** | Excellent (kernel-space) | Excellent (uses WireGuard) | Good (user-space) | Good | Variable (depends on server) |
| **Cost** | $0 | $0 (3 users) / $6/month (team) | $0 | $0 (25 devices) / $10/month | ~$3-5/month |
| **Config complexity** | Medium (port forward, DDNS) | **Low** (install and go) | High (PKI, certificates) | Low | Minimal (app) |
| **ARM64 RPi** | Yes | Yes | Yes | Yes | Client only |

## Tailscale: how it would change the lab architecture

Tailscale uses WireGuard under the hood, but adds a **coordination server** (Tailscale cloud) that manages key exchange and NAT traversal automatically. The architectural impact is significant:

```
CURRENT ARCHITECTURE (self-hosted WireGuard):
    Internet -> DDNS -> Router (port forward :51820) -> RPi -> WireGuard container
    Requirements: public IP (or DMZ from provider), DDNS, port forwarding

ARCHITECTURE WITH TAILSCALE:
    Internet -> Tailscale coordination server -> NAT hole-punching P2P
    RPi <---- direct WireGuard tunnel ----> Smartphone/Laptop
    Requirements: NONE (no port forward, no DDNS, works behind CGNAT)
```

**Installing Tailscale on the Raspberry Pi:**

```bash
# Installation
curl -fsSL https://tailscale.com/install.sh | sh

# Activation (opens the browser for login)
sudo tailscale up

# Verification: shows the assigned Tailscale IP (100.x.x.x)
tailscale ip -4

# On the client (phone/laptop): install Tailscale, login with the same account
# -> Direct tunnel RPi <-> Client, without port forwarding
```

**Impact on lab services:**

| Service | With WireGuard | With Tailscale | Difference |
|---|---|---|---|
| Remote LAN access | Yes (full tunnel) | Yes (direct access to Pi) | Tailscale: no split tunnel, only Tailscale devices |
| **Exposed honeypot** | Port forward :2222 | **Not possible** (Tailscale does not expose ports to the Internet) | **Dealbreaker**: Tailscale is not designed to expose public services |
| Remote Pi-hole | Yes (DNS via tunnel) | Yes (set Pi as exit node) | Similar |
| Wazuh Dashboard | Yes (via VPN tunnel) | Yes (via Tailscale network) | Similar |
| CGNAT cost | Requires DMZ from provider or Ngrok | No additional cost | Tailscale wins |

> **Why I chose WireGuard over Tailscale:** The project requires **exposing the honeypot to the Internet**. Tailscale is designed to connect private devices, not to expose public services. With Tailscale, the honeypot's port 2222 would not be reachable by external attackers - defeating the entire purpose of the project. Self-hosted WireGuard allows precise control over which ports are exposed and which are not.

> **When to use Tailscale:** If the project were only "NAS + remote access" (without a honeypot), Tailscale would be the best choice: zero network configuration, works behind any NAT, no DDNS needed.

## NordVPN/Surfshark: why they make no sense for a homelab

Commercial VPNs (NordVPN, ExpressVPN, Surfshark) solve a different problem:

| | Self-hosted VPN (WireGuard) | Commercial VPN (NordVPN) |
|---|---|---|
| **Purpose** | Access YOUR network remotely | Hide YOUR traffic from the provider |
| **Traffic** | Smartphone -> your home -> Internet | PC -> NordVPN server -> Internet |
| **LAN access** | Yes (you can reach NAS, Wazuh) | **No** (you are not connected to your LAN) |
| **Exit IP** | Your home IP | NordVPN IP (different country) |
| **Honeypot** | You can expose services | You cannot expose anything |
| **Privacy from provider** | No (the provider sees your IP) | Yes (the provider only sees traffic to NordVPN) |

NordVPN does not give you remote access to the Raspberry Pi. It is a service for browsing anonymously, not for managing a homelab.

## OpenVPN: when to prefer it over WireGuard

OpenVPN has a specific advantage: it can operate on **TCP port 443**, making it indistinguishable from HTTPS traffic. This is useful in:

- **Corporate networks** that block everything except HTTP/HTTPS
- **Countries with censorship** that actively block VPN protocols (China, Russia, Iran)
- **Hotel/airport Wi-Fi** with restrictive firewalls

```bash
# OpenVPN installation on Docker (alternative to WireGuard)
docker run -d \
    --name openvpn \
    --restart=always \
    --cap-add=NET_ADMIN \
    -p 443:1194/tcp \
    -v /home/pi/openvpn:/etc/openvpn \
    kylemanna/openvpn

# PKI initialization (requires interaction)
docker exec openvpn ovpn_genconfig -u tcp://miodominio.ddns.net:443
docker exec -it openvpn ovpn_initpki

# Generate a client
docker exec openvpn easyrsa build-client-full client1 nopass
docker exec openvpn ovpn_getclient client1 > client1.ovpn
```

The downside: ~100,000 lines of code (vs 4,000 for WireGuard), a much larger attack surface, and complex PKI management.

## Cloudflare Tunnel: the alternative to Ngrok for exposing services

If you use Cloudflare for DNS, **Cloudflare Tunnel** is a free and more stable alternative to Ngrok:

```bash
# cloudflared installation
curl -fsSL https://pkg.cloudflare.com/cloudflared-ascii.repo | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install cloudflared -y

# Authentication
cloudflared tunnel login

# Create a tunnel
cloudflared tunnel create homelab-honeypot

# Configure the tunnel to expose the honeypot
cat > ~/.cloudflared/config.yml <<EOF
tunnel: <TUNNEL_ID>
credentials-file: /root/.cloudflared/<TUNNEL_ID>.json
ingress:
  - hostname: honeypot.miodominio.com
    service: ssh://localhost:2222
  - service: http_status:404
EOF

# Start the tunnel
cloudflared tunnel run homelab-honeypot
```

| | Ngrok | Cloudflare Tunnel |
|---|---|---|
| **Cost** | Free (1 tunnel, random URL) | Free (unlimited, fixed domain) |
| **URL** | Changes on every restart (free tier) | Fixed (your domain) |
| **Protocols** | TCP, HTTP, HTTPS | HTTP, HTTPS, SSH, TCP |
| **Speed** | Good | Excellent (global Cloudflare network) |
| **Persistence** | Requires screen/systemd | Native systemd service |
| **Requirements** | Ngrok account | Domain on Cloudflare (free) |
