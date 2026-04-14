>  [Italiano](driver-docker.md) |  **English**

# Docker Network Modes Compared

Docker offers several network drivers. The choice of driver has a direct impact on isolation, visibility, and performance.

## Bridge (default)

```
[Container] ──── [Docker Bridge (172.17.0.1)] ──── NAT ──── [Rete fisica]
```

- Each container receives a private IP in Docker's internal subnet (172.17.0.0/16)
- Outbound traffic passes through NAT (Network Address Translation)
- **Problem:** All outgoing packets have the Raspberry Pi's address as the source IP. Pi-hole cannot distinguish which client made the DNS query - it only sees the Docker gateway IP
- **Problem:** Exposing ports requires `-p 80:80` (port mapping) - conflict if the host is already using that port

## MacVLAN

```
[Container (MAC: aa:bb:cc:dd:ee:01, IP: 192.168.0.250)] ──── [Rete fisica]
[Host (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.0.102)]      ──── [Rete fisica]
```

- The container gets a **virtual MAC address** and an IP on the physical network
- It appears as a separate physical device on the LAN
- **Advantage:** Dedicated IP, no NAT, no port mapping
- **Critical limitation:** By Linux kernel design, the host **cannot communicate** with MacVLAN containers on the same interface. Traffic between host and container is dropped at the kernel level (anti-spoofing measure)

## IPVLAN (L2 mode)

```
[Container (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.150.69)] ──── [Rete fisica / VLAN]
[Host (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.0.102)]       ──── [Rete fisica]
```

- The container **shares the host's MAC address** but has a different IP
- It operates at Layer 2 - Ethernet frames are sent directly onto the physical network
- **Advantage:** Compatible with environments where security policies limit the number of MACs per port (802.1X, port security on managed switches)
- **Same limitation** as MacVLAN: host and container cannot communicate directly

| Feature | Bridge | MacVLAN | IPVLAN L2 |
|---|---|---|---|
| NAT | Yes | No | No |
| Real IP on LAN | No | Yes | Yes |
| Dedicated MAC address | No | Yes (virtual) | No (shared with host) |
| Host ↔ Container | Yes | **No** | **No** |
| Port mapping required | Yes | No | No |
| Client IP visibility | Gateway IP only | Real client IP | Real client IP |
| Port-security compatibility | N/A | May cause issues | Compatible |
