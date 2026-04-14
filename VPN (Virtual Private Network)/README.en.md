>  [Italiano](README.md) |  **English**

# VPN Server - WireGuard on Docker with wg-easy

A comprehensive guide to turning a Raspberry Pi into a VPN server using WireGuard. This guide stems from my direct experience and covers not only the software installation, but also the complex network configurations (DMZ, Double NAT, DDNS) that were necessary to make everything work with an FWA (Fixed Wireless Access) provider.

---

## In brief

WireGuard is a modern VPN protocol with ~4,000 lines of code (compared to ~100,000+ for OpenVPN), fixed cryptography based on ChaCha20-Poly1305 and Curve25519, and a Noise IK handshake that completes in a single round-trip with 4 Diffie-Hellman operations. Its architectural innovation is the Cryptokey Routing Table, which merges routing and encryption into a single operation, making the protocol inherently resistant to spoofing.

---

## Table of Contents

| Document | Content |
|---|---|
| [Theory: VPN and WireGuard](docs/teoria-wireguard.en.md) | What a VPN is, why WireGuard, cryptographic suite, Noise IK handshake (4 DH), Cryptokey Routing Table, transparent roaming |
| [Network: DMZ and Double NAT](docs/rete-dmz.en.md) | The Double NAT problem with FWA providers, DMZ solution, prerequisites, router configuration (static IP, DDNS, port forwarding) |
| [Installation](docs/installazione.en.md) | Directory creation, Docker Compose with parameter explanations, iptables PostUp/PostDown rules, startup, annotated `wg show` output |
| [Alternatives compared](docs/alternative.en.md) | WireGuard vs Tailscale vs OpenVPN vs ZeroTier vs NordVPN, architectural impact of Tailscale, OpenVPN Docker installation, Cloudflare Tunnel |
| [Troubleshooting and usage](docs/troubleshooting.en.md) | 3 real problems and solutions (bootloop, DNS limbo, 4G MTU), daily usage, verification tests |

---

Next step: [ADS Blocker](../ADS%20Blocker/) - Pi-hole as a DNS sinkhole for blocking ads and tracking.
