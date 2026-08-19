>  [Italiano](lan-health-check.md) |  **English**

# Runbook 07 - LAN health check

> **When to use this runbook:** you want a complete health check of the home network - connectivity, integrity, security - to be run periodically or when "the network is doing weird things". The runbook is structured to adapt to four physical scenarios: **with or without a managed switch** and **with or without a modem/router with built-in hardware defense**.

You proceed by ISO/OSI layers, from the cable to the application, because a low health problem masquerades as a high problem (see [Runbook 00](triage-diagnostica.en.md)).

---

## Scenario matrix

The checks change depending on your hardware. Identify your column:

| | **Without a managed switch** | **With a managed switch** |
|---|---|---|
| **Simple modem/router** | Flat network, a single broadcast domain. Segmentation only in software (IPVLAN on the Pi). Minimal perimeter defense. | Real 802.1Q VLANs possible. Perimeter defense still software. |
| **Modem/router with HW defense** | Firewall/IPS at the gateway, but a flat internal network. The gateway filters N/S traffic but not internal E/W. | The most robust setup: real VLANs + hardware perimeter filtering. The project's target. |

Key concepts that recur below:
- **North-South (N/S) traffic:** between the LAN and the Internet. The gateway/modem filters it.
- **East-West (E/W) traffic:** between devices on the same LAN. The managed switch / VLANs filter it (if they filter it), **not** the modem.

---

## Layer 1 - Physical: link and cable

```bash
# On the Pi: does the interface have carrier, and at what speed does it negotiate?
sudo ethtool end0 | grep -E "Speed|Duplex|Link detected"
# Expected: Speed: 1000Mb/s, Duplex: Full, Link detected: yes
# Speed 100Mb/s on a gigabit link <-- poor/damaged cable or degraded port
# Link detected: no <-- cable unplugged, dead switch port, or physical problem

# Errors on the interface (a marginal cable accumulates CRC errors)
ip -s link show end0 | grep -A2 RX
# Expected: errors 0, dropped 0. Growing numbers <-- physical L1/L2 problem
```

> **With PoE:** if the Pi or the switch are PoE-powered, an insufficient PoE budget causes links that drop under load. Check the switch budget.

---

## Layer 2 - Data link: switch and VLAN

### 2a. Without a managed switch (flat network)

Segmentation, if any, is the Pi's software one (IPVLAN on `end0.150`). There is no hardware isolation between ports: all devices see each other at L2.

```bash
# Is the software VLAN on the Pi up?
ip -br link show end0.150     # expected: UP
# Who is in the broadcast domain (the whole LAN is a single segment)
ip neigh show | grep -v FAILED
```

Security implication: without a managed switch, a compromised device on the LAN can talk to all the others (unfiltered E/W traffic). The only E/W defense is each device's host firewall. This is why hardening the individual host matters more on a flat network.

### 2b. With a managed switch (real 802.1Q VLANs)

```bash
# Do the VLAN tags actually pass? Capture tagged frames on the trunk
sudo tcpdump -i end0 -e -n vlan 2>/dev/null | head -5
# Expected: frames with "vlan 150" in the 802.1Q header -> tagging works end-to-end

# Does the tagged sub-interface receive traffic?
ip -s link show end0.150 | grep -A2 RX
```

Inter-VLAN isolation check (must be watertight if so designed): see the test in [Runbook 05, section 8](verifica-difese-attive.en.md). On a managed switch, enable **DHCP snooping** and **Dynamic ARP Inspection** if available: they neutralize rogue DHCP and ARP spoofing at the hardware level.

---

## Layer 3 - Network: IP, gateway, DHCP

```bash
# Address, gateway and default route consistent?
ip -br addr show
ip route | grep default          # expected: default via 192.168.0.1
ping -c3 192.168.0.1             # does the gateway respond?

# IP conflicts (two devices with the same IP make the network drop intermittently)
sudo apt install -y arp-scan >/dev/null 2>&1
sudo arp-scan --interface=end0 --localnet | sort | uniq -d -w 17
# A MAC that answers for two IPs, or two MACs for one IP <-- conflict/anomaly

# DHCP scope: which server assigns the IPs? (must be only the router)
sudo nmap --script broadcast-dhcp-discover 2>/dev/null | grep "Server Identifier"
# More than one Server Identifier <-- rogue DHCP (see Runbook 06)
```

---

## Layer 3.5 - The modem/router: what does it really filter?

Here the "with or without hardware defense" distinction comes in. A modem/router with built-in firewall/IPS filters N/S traffic; a simple one only does NAT. You must verify **what** your gateway actually blocks, not what the box promises.

```bash
# What is EXPOSED from the outside? (the real test of the N/S perimeter defense)
# From outside (VPS/4G) towards your public IP, or with an online port-scan service:
#   - ONLY the ports you forwarded on purpose must show as open
#     (51820/UDP WireGuard, 2222/TCP honeypot) and nothing else.
# From the Pi, check what the router forwards/exposes:
curl -s https://api.ipify.org ; echo        # your public IP

# Does the modem do double NAT? (typical when modem and router are two devices)
traceroute -n -m 3 8.8.8.8
# Two hops in RFC1918 (e.g. 192.168.1.1 then 192.168.0.1) before exiting <-- double NAT
```

What to verify on the gateway, by type:

| Modem/router type | What it MUST filter | How to verify it |
|---|---|---|
| **Simple (NAT only)** | Blocks unsolicited inbound (implicit NAT). No IPS. | Port scan from outside: only the forwarded ports must open |
| **With HW defense (firewall/IPS)** | Inbound + malicious patterns + sometimes DNS/reputation filtering | Beyond the port scan, check the router's logs/dashboard for IPS events |

Fixed points regardless of type:
- The **router admin UI must NOT be reachable from the Internet** (LAN only). Verify from outside that the router's port 80/443 is closed.
- The **router credentials must be changed** from the default: the gateway is the master of DNS, DHCP and port forwarding for the whole house.
- If the modem has a **DMZ**, know what you put in it: a host in the DMZ is exposed and must be treated like the honeypot, not like the trusted LAN.

---

## Layers 4-7 - DNS, egress, inventory

```bash
# DNS: am I using the right resolver and does it filter?
resolvectl status | grep "DNS Servers"           # expected: 192.168.0.250 (Pi-hole)
dig @192.168.0.250 ads.doubleclick.net +short    # expected: 0.0.0.0

# DNS leak: is some device bypassing Pi-hole towards an external DNS?
# On the Pi/gateway, look for outbound DNS queries (53) towards IPs != Pi-hole
sudo tcpdump -i end0 -n 'udp port 53 and not host 192.168.0.250' 2>/dev/null | head
# DNS traffic towards 8.8.8.8/1.1.1.1 from a client <-- that client bypasses the sinkhole

# Inventory: who is on my LAN? (compare with the expected list)
sudo arp-scan --interface=end0 --localnet
# A MAC/device you do not recognize <-- investigate (legitimate guest or intruder?)

# Internet egress health
ping -c5 1.1.1.1 | tail -2      # packet loss and latency towards the Internet
```

---

## LAN scorecard

```
DATE: __________  SCENARIO: [ ]no switch [ ]managed switch  [ ]simple modem [ ]HW modem
[ ] L1  Link 1000/full, 0 errors
[ ] L2  VLAN tags verified (if managed switch) / broadcast domain known
[ ] L3  Gateway reachable, no IP conflict, a single DHCP
[ ] L3.5 From outside only the forwarded ports open; router UI not exposed; router credentials changed
[ ] L4  DNS = Pi-hole, sinkhole active, no DNS leak
[ ] L7  Device inventory compared with expected; no unknown MAC
```

---

## Prevention

- Keep a **device inventory** (MAC -> name -> IP) as a baseline: it makes spotting an intruder immediate.
- With a managed switch: enable **DHCP snooping** and **Dynamic ARP Inspection**; they are the hardware L2 defenses against MITM.
- With a simple modem: compensate for the perimeter defense with rigorous host firewalls on every device (flat network = zero trust between hosts).
- Force all clients to use Pi-hole (block outbound 53 towards the outside on the gateway, except from Pi-hole) to eliminate DNS leaks.
- Automate the inventory and the L1-L4 checks and have Wazuh alert on them.

---

## Links

- Suspected MITM/ARP/rogue DHCP in detail -> [Runbook 06: post-downtime integrity](integrita-post-downtime.en.md)
- Proving inter-VLAN isolation -> [Runbook 05: verifying active defenses](verifica-difese-attive.en.md)
- Full network topology of the lab -> [docs/topologia-rete](../../docs/topologia-rete.en.md)
- VLAN and IPVLAN theory -> [VLAN / teoria-vlan](../../VLAN%20(Virtual%20LAN)/docs/teoria-vlan.en.md)
