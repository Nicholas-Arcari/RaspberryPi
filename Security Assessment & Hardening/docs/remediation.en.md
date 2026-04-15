>  [Italiano](remediation.md) |  **English**

# Phase 4-6: Remediation - Locking Down the Network

## Phase 4: Firewall with UFW

### Abandoning the DMZ

I disabled the DMZ on the router and configured an internal firewall (UFW) to create a network "cage" on the Raspberry Pi.

### The Rule Ordering Mistake (a painful lesson)

In the first attempt to isolate the Raspberry Pi, I blocked all traffic towards the local network:

```bash
sudo ufw deny out from any to 192.168.0.0/24
```

**Result:** I cut the Raspberry Pi off from the Internet. It could no longer reach the router/gateway (`192.168.0.1`) to download updates or resolve DNS.

**The technical explanation:** UFW (and iptables under the hood) evaluates rules **in the order they were inserted**. The first matching rule decides the fate of the packet. By blocking `192.168.0.0/24`, I also blocked `192.168.0.1` (the gateway) because it is part of that subnet.

### The Correct Order (gateway FIRST, THEN the block)

```bash
# 1. Default policy: block all incoming traffic
sudo ufw default deny incoming

# 2. CRITICAL ORDER for outbound traffic:
#    First ALLOW the gateway (otherwise no Internet access)
sudo ufw allow out from any to 192.168.0.1

#    Then BLOCK the rest of the LAN (prevents lateral movement)
sudo ufw deny out from any to 192.168.0.0/24

# 3. Selective inbound permissions (LAN only)
sudo ufw allow from 192.168.0.0/24 to any port 22    # Administrative SSH
sudo ufw allow from 192.168.0.0/24 to any port 443   # Wazuh Dashboard
```

**How iptables interprets these rules:**

```
Chain OUTPUT:
  Rule 1: -d 192.168.0.1 -> ACCEPT    <-- The gateway passes (it is the first rule)
  Rule 2: -d 192.168.0.0/24 -> REJECT  <-- Everything else on the LAN is blocked
  Rule 3: (default policy: ACCEPT)     <-- Internet (outside the LAN) works normally
```

A packet destined for `192.168.0.1` matches Rule 1 and is accepted. A packet destined for `192.168.0.50` (a LAN PC) does not match Rule 1, matches Rule 2, and is blocked.

---

## Phase 5: The "Disconnected" Agent Mystery

### The Problem

After configuring UFW with `default deny incoming`, I noticed on the Dashboard that the Wazuh agent installed on my Kali machine showed as "Disconnected", even though the machine was powered on and on the same network.

### The Cause

In the rush to close all ports, I had also blocked the Wazuh communication ports:

- **Port 1514/TCP**: event channel (agents send logs to the Manager)
- **Port 1515/TCP**: registration channel (enrollment of new agents)

### The Fix

```bash
sudo ufw allow from 192.168.0.0/24 to any port 1514 proto tcp  # Event channel
sudo ufw allow from 192.168.0.0/24 to any port 1515 proto tcp  # Registration channel
```

By restricting access to the local network (`192.168.0.0/24`), only agents on my LAN can communicate with the Manager. An attacker from the Internet cannot register fake agents or send manipulated events.

---

## Phase 6: Internet Exposure - CGNAT and Ngrok

### The Double NAT Problem

When I tried to expose the Honeypot to the Internet using the router's Port Forwarding, it did not work.

**Diagnosis:** By checking the router's WAN IP, I discovered it was a private address (`192.168.x.x`). My Internet provider (FWA connection with antenna) was placing me behind a **CGNAT (Carrier-Grade NAT)**: an additional NAT layer managed by the provider.

```
Internet -> [Provider CGNAT (private IP)] -> [TP-Link Router (private IP)] -> [Raspberry Pi]
            ^ Port forwarding is blocked here
```

In a CGNAT setup, my router does not have a public IP - it has a private IP assigned by the antenna. Even with port forwarding perfectly configured on the TP-Link, traffic from the Internet never reaches my router because the provider's NAT blocks it.

### The Solution: Ngrok (tunneling)

**Ngrok** creates a reverse tunnel: the Raspberry Pi connects to an Ngrok server (outbound - so it works even behind CGNAT), and Ngrok assigns a temporary public address that forwards traffic to the tunnel.

```
Internet -> [Ngrok Server (0.tcp.eu.ngrok.io:xxxxx)] <-- TCP tunnel <-- [Raspberry Pi port 2222]
```

#### Installation and Usage

```bash
# Installation
sudo apt install screen -y

# Start a persistent session with screen
screen

# Start the Ngrok tunnel on the Honeypot port
ngrok tcp 2222
```

**Why `screen`:** Ngrok is a foreground process - if you close the SSH terminal, Ngrok dies and the tunnel goes down. `screen` creates a persistent terminal session that continues running even after logout.

- **Detach (exit without closing):** `CTRL+A` then `D`
- **Reattach to the session:** `screen -r`

#### Free Plan Limitations

- The public address (e.g., `0.tcp.eu.ngrok.io:12345`) and port **change with every tunnel restart**
- No fixed domain (requires a paid plan)
- If the Raspberry Pi reboots, you need to re-enter screen and restart Ngrok manually

---

## Summary of Vulnerabilities Found and Fixed

| # | Vulnerability | Risk | Solution |
|---|---|---|---|
| 1 | Active DMZ - all ports exposed to the Internet | Critical | Removed DMZ, configured selective port forwarding |
| 2 | Real SSH (port 22) exposed to the Internet | Critical | UFW: SSH allowed only from LAN |
| 3 | Wazuh Dashboard/API exposed to the Internet | High | UFW: ports 443/55000/9200 allowed only from LAN |
| 4 | No network isolation for the Honeypot container | High | UFW: blocked outbound traffic to LAN (except gateway) |
| 5 | Wazuh Agent ports blocked | Medium | UFW: opened ports 1514/1515 from LAN |
| 6 | CGNAT prevents port forwarding | N/A (architecture) | Ngrok tunnel as an alternative solution |
