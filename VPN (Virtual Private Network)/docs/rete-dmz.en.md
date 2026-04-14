>  [Italiano](rete-dmz.md) |  **English**

# The Network Challenge: DMZ and Double NAT

## The Double NAT problem

Before configuring WireGuard, I had to solve a network problem that was completely blocking port forwarding.

My Internet connection comes through an **FWA antenna** (provider: Comeser) connected to my personal router (TP-Link Archer C50). This created a chain:

```
Internet -> [Provider Antenna (NAT #1)] -> [TP-Link Router (NAT #2)] -> [Raspberry Pi]
```

**What is CGNAT (Carrier-Grade NAT):** The provider assigns my antenna a **private** IP (such as `10.x.x.x` or `100.64.x.x`) instead of a public IP. This means my router, despite having a "WAN IP", actually has an IP that is not reachable from the Internet.

**How I discovered this:** When checking the WAN IP on the router, I saw a `192.168.x.x` address - clearly a private IP. Port forwarding on the TP-Link was useless because traffic was being blocked upstream, at the provider's NAT.

## The solution: DMZ on the provider

I contacted the FWA provider's technical support and asked them to put my router's IP in the **DMZ** (Demilitarized Zone), meaning to configure a **1:1 NAT** that forwards all incoming traffic directly to my router, bypassing the provider's firewall.

```
Internet -> [Provider Antenna (DMZ -> all traffic to my router)] -> [TP-Link Router] -> [Raspberry Pi]
```

After this change, my router sees a public WAN IP and port forwarding works normally.

> **Security note:** With DMZ active, the router is directly exposed to the Internet. I took these precautions:
> - Disabled remote router management (no admin access from the outside)
> - Changed the router admin password to a strong one
> - Opened only the strictly necessary ports in port forwarding
> - Active monitoring with Wazuh of Raspberry Pi access

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Hardware** | Raspberry Pi with Raspberry Pi OS and Docker installed |
| **Static local IP** | Assign a fixed IP to the Pi (e.g., `192.168.0.102`) via DHCP reservation on the router |
| **DDNS** | Dynamic domain (e.g., No-IP) pointing to the home public IP |
| **Port forwarding** | Port 51820 UDP forwarded to the Raspberry Pi |
| **Public IP** | Or DMZ configured on the provider (for CGNAT) |

---

## Router Configuration

### 1. Static IP for the Raspberry Pi

On the router (TP-Link -> DHCP -> Address Reservation):

- Raspberry Pi's MAC Address
- Reserved IP: `192.168.0.102`

This ensures that port forwarding always points to the correct IP, even after a Pi reboot.

### 2. DDNS (Dynamic DNS)

The public IP assigned by the provider can change periodically (dynamic IP). A **DDNS** (Dynamic Domain Name System) service maps a fixed domain name (e.g., `miodominio.ddns.net`) to the current public IP.

I used **No-IP** (https://www.noip.com):

1. Registered a free account
2. Created a hostname (e.g., `miodominio.ddns.net`)
3. Configured the DDNS client on the router (TP-Link -> Dynamic DNS -> No-IP)

The router automatically updates the domain to IP mapping every time the public IP changes.

### 3. Port forwarding

On the router (TP-Link -> Forwarding -> Virtual Servers):

| Field | Value |
|---|---|
| Service Port | 51820 |
| Internal Port | 51820 |
| IP Address | 192.168.0.102 |
| Protocol | **UDP** |

> **Why UDP and not TCP:** WireGuard uses UDP exclusively. Unlike OpenVPN which can operate over TCP (port 443, to resemble HTTPS traffic), WireGuard is designed around UDP to minimize latency. The protocol handles packet retransmission internally, without the overhead of TCP.
