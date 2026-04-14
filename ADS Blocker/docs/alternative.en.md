>  [Italiano](alternative.md) |  **English**

# Why Pi-hole and Not the Alternatives

## Pi-hole vs AdGuard Home vs Blocky vs NextDNS

| Aspect | Pi-hole | AdGuard Home | Blocky | NextDNS |
|---|---|---|---|---|
| **Architecture** | dnsmasq + FTL (C) | CoreDNS custom (Go) | Go, YAML config | Cloud SaaS |
| **Self-hosted** | Yes | Yes | Yes | **No** (NextDNS servers) |
| **Interface** | Web (PHP/lighttpd) | Web (integrated, no dependencies) | None (config file only) | Web (cloud) |
| **DNS-over-HTTPS (DoH)** | Not native (requires proxy) | **Yes** (native, server and client) | **Yes** (native) | **Yes** (cloud) |
| **DNS-over-TLS (DoT)** | Not native | **Yes** (native) | **Yes** | **Yes** |
| **Per-client filtering** | Partial (group management) | **Yes** (per-client rules) | **Yes** | **Yes** |
| **DHCP server** | Yes | Yes | No | No |
| **Resources (RAM)** | ~120MB | ~70MB | ~20MB | 0 (cloud) |
| **RPi ARM64** | Yes | Yes | Yes | N/A (cloud) |
| **Blocklists** | Gravity (SQLite, 80k+ domains) | AdBlock-style filters (more flexible) | Link list in YAML | Presets + custom |
| **Community** | Huge (oldest, best documented) | Large (rapidly growing) | Small (niche) | Medium |
| **Cost** | $0 | $0 | $0 | $0 (300k queries/month) / $20/year |

## AdGuard Home: The Main Alternative - When to Choose It

AdGuard Home has two advantages Pi-hole lacks: **native DoH/DoT** (DNS traffic between AdGuard and upstream is encrypted without additional proxies) and **per-client filtering** (you can apply different blocklists to different devices - e.g., more aggressive blocklist for children, more permissive for your PC).

**Docker installation (same ports as Pi-hole):**

```bash
docker run -d \
    --name adguardhome \
    --restart=always \
    --net macvlan_lan \
    --ip 192.168.0.250 \
    -v /home/pi/adguard/work:/opt/adguardhome/work \
    -v /home/pi/adguard/conf:/opt/adguardhome/conf \
    adguard/adguardhome

# Setup wizard at http://192.168.0.250:3000 (first launch)
# After setup, dashboard at http://192.168.0.250:80
```

**Why I chose Pi-hole over AdGuard Home:**

1. **Community and documentation**: Pi-hole is the most mature project, with thousands of guides and troubleshooting resources available. For an educational project, documentation matters
2. **Wazuh integration**: Pi-hole writes logs in standard syslog format (`/var/log/pihole.log`), easily ingestible by Wazuh. AdGuard Home uses a proprietary format that requires custom decoders
3. **FTL engine**: Pi-hole's FTL engine is written in C and handles queries with sub-millisecond latency. AdGuard Home in Go is still fast, but FTL is more efficient on constrained hardware like the Pi

**When to choose AdGuard Home:** If you need native DoH/DoT (without configuring a proxy like `cloudflared`), or if you want different rules for different devices (e.g., children vs adults).

## Blocky: The Minimal Alternative for YAML Enthusiasts

Blocky is for those who find Pi-hole and AdGuard Home "too much" - no web interface, just a YAML file:

```bash
# Docker installation
docker run -d \
    --name blocky \
    --restart=always \
    -p 53:53/udp -p 53:53/tcp \
    -v /home/pi/blocky/config.yml:/app/config.yml \
    spx01/blocky

# config.yml
cat > /home/pi/blocky/config.yml <<'EOF'
upstream:
  default:
    - 1.1.1.1
    - 8.8.8.8
blocking:
  blackLists:
    ads:
      - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
  clientGroupsBlock:
    default:
      - ads
port: 53
httpPort: 4000
EOF
```

~20MB of RAM, no dependencies, declarative configuration. Ideal for those who prefer Git + YAML over web dashboards.

## Questions an Analyst Would Ask

**"Does DoH (DNS-over-HTTPS) make Pi-hole useless?"**

Partially. If a device uses DoH directly (Firefox with DoH enabled pointing to Cloudflare), DNS queries **completely bypass Pi-hole** because they travel over HTTPS on port 443, not over DNS on port 53.

Mitigations:
1. **Block the IPs of known DoH resolvers** with UFW:
```bash
# Block major DoH resolvers (forces devices to use Pi-hole)
sudo ufw deny out to 1.1.1.1 port 443 comment "Block Cloudflare DoH"
sudo ufw deny out to 8.8.8.8 port 443 comment "Block Google DoH"
sudo ufw deny out to 9.9.9.9 port 443 comment "Block Quad9 DoH"
```
2. **Disable DoH in browsers** via group policy (enterprise) or manual configuration
3. **Use Pi-hole itself as a DoH resolver** with `cloudflared` as an upstream proxy

**"Is a DNS ad blocker enough for privacy?"**

No. DNS blocking prevents loading resources from known tracking domains, but it does not protect against:
- **Browser fingerprinting**: the server identifies the device by browser characteristics (canvas, WebGL, installed fonts) without cookies
- **First-party tracking**: if `example.com` tracks its own users on its own domain, Pi-hole does not block it (it only blocks third-party domains)
- **App-level tracking**: many mobile apps use tracking SDKs with hardcoded IPs, not resolvable via DNS

For comprehensive protection you need: Pi-hole (DNS) + uBlock Origin (browser) + VPN (hides IP) + browser hardening (Firefox with resistFingerprinting).
