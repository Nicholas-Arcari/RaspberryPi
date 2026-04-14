>  [Italiano](README.md) |  **English**

# Pi-hole - DNS Sinkhole for Ad and Tracking Blocking

This guide documents the installation of Pi-hole on Docker with a MacVLAN network, configuring the router to use it as the primary DNS, and the real-world issues I encountered (spoiler: the port 80 conflict with OpenMediaVault).

---

## How It Works in Brief

Pi-hole acts as a **local DNS server** on the network. All DNS queries from devices pass through it: if the requested domain is on a blocklist (advertising, tracking), Pi-hole responds with a null address (`0.0.0.0`) and the resource is never downloaded. From the browser's perspective, the ad server simply does not exist.

```
Device -> Pi-hole (192.168.0.250) -> Is the domain on the blocklist?
                                      |-- YES -> Responds 0.0.0.0 (blocked)
                                      +-- NO  -> Forwards to upstream DNS (8.8.8.8, 1.1.1.1)
```

Unlike browser-based ad blockers (uBlock Origin, AdBlock), Pi-hole protects **all** devices on the network (TVs, IoT, smartphones, consoles) and blocks tracking from apps as well, not just from the browser.

---

## Table of Contents

| Document | Content |
|---|---|
| [DNS Protocol](docs/protocollo-dns.en.md) | DNS resolution (recursive vs iterative), hierarchy, record types with `dig` examples, DNS packet anatomy, where Pi-hole fits in |
| [Pi-hole Installation](docs/installazione-pihole.en.md) | Port 80 conflict with OMV, Docker + MacVLAN solution, network configuration, Docker Compose, startup and password |
| [Network Configuration](docs/configurazione-rete.en.md) | Router as DNS relay, DHCP configuration, DHCP leases and client updates, DNS-over-HTTPS (DoH) issue |
| [FTL Engine](docs/ftl-engine.en.md) | FTL (Faster Than Light) engine, gravity.db (SQLite), regex/wildcard blocking, DNSSEC |
| [Alternatives](docs/alternative.en.md) | Pi-hole vs AdGuard Home vs Blocky vs NextDNS, AdGuard and Blocky Docker installation, analyst questions (DoH, privacy) |
| [Troubleshooting](docs/troubleshooting.en.md) | Verifying operation (dashboard, query log, speedtest), container commands, MacVLAN issues |

---

## Future Developments

The MacVLAN setup allows adding more containers with dedicated IPs on the local network, simply by changing the IP address in Docker Compose:

| Service | Dedicated IP | Port |
|---|---|---|
| Pi-hole | 192.168.0.250 | 80, 53 |
| Honeypot | 192.168.0.251 | 2222, 2223 |
| Home Assistant | 192.168.0.252 | 8123 |

---

Next step: [Honeypot](../Honeypot/) - deploying Cowrie to catch attackers.
