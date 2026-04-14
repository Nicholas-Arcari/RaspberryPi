>  [Italiano](kernel-ipvlan.md) |  **English**

# Deep Dive: Packet Flow in IPVLAN L2 at the Kernel Level

To understand what actually happens when a container on IPVLAN L2 sends or receives a packet, we need to go down to the Linux kernel level.

## Outbound Packet (container → physical network)

```
[Processo nel container]
    │
    ▼ write() sulla socket
[Network namespace del container]
    │
    ▼ Il kernel costruisce il frame Ethernet
[eth0@if9 - interfaccia IPVLAN slave]
    │ IP sorgente: 192.168.150.69
    │ MAC sorgente: 2c:cf:67:b2:47:ea  ← MAC dell'HOST (condiviso)
    │
    ▼ Il driver IPVLAN L2 bypassa il routing del container
[end0.150 - interfaccia VLAN parent]
    │
    ▼ Il kernel aggiunge il tag 802.1Q (VLAN ID 150)
[end0 - interfaccia fisica]
    │
    ▼ Frame Ethernet esce sul cavo
[Switch → Rete]
```

**Key point**: in L2 mode, the IPVLAN driver operates as a **software bridge**. It does not pass through the container's routing tables - the frame is delivered directly to the parent interface. This is why IPVLAN L2 is faster than bridge: it skips netfilter, NAT, and routing.

In **L3** mode (not used in our setup), the driver operates as a router: the packet traverses the container's routing tables and netfilter, allowing more granular policies but with higher overhead.

## Inbound Packet (physical network → container)

```
[Switch → Cavo Ethernet]
    │
    ▼ Frame Ethernet con tag 802.1Q VLAN 150
[end0 - interfaccia fisica]
    │
    ▼ Il kernel legge il tag: VLAN ID = 150
[end0.150 - interfaccia VLAN]
    │
    ▼ Il driver IPVLAN controlla l'IP destinazione
    │ Decisione: 192.168.150.69 appartiene a un container IPVLAN?
    │
    ├── SI → consegna al network namespace del container
    │         [eth0@if9 → processo nel container]
    │
    └── NO → consegna allo stack di rete dell'host
              (ma l'host non ha IP su end0.150, quindi il pacchetto viene scartato)
```

**The dispatch mechanism**: when a frame arrives on `end0.150`, the IPVLAN driver compares the destination IP against an internal table that maps `IP → network namespace`. If it finds a match, it delivers the packet to the corresponding container's namespace. If it does not find one, the packet is passed up to the host's network stack. Since the host has no IP address configured on `end0.150`, the packet is discarded - this is the technical reason why **the host cannot communicate with IPVLAN containers**.

## ARP in IPVLAN vs MacVLAN: The Fundamental Difference

The ARP (Address Resolution Protocol) protocol resolves `IP → MAC address` on the LAN. The way ARP works is the **key architectural difference** between MacVLAN and IPVLAN:

**MacVLAN:**
```
Router ARP request: "Chi ha 192.168.150.69?"
    │
    ▼
Container risponde con MAC VIRTUALE: "192.168.150.69 è aa:bb:cc:dd:ee:01"
    │
    ▼
ARP table del router: 192.168.150.69 → aa:bb:cc:dd:ee:01
ARP table del router: 192.168.0.102  → 2c:cf:67:b2:47:ea
                      (2 MAC diversi sulla stessa porta fisica)
```

**IPVLAN:**
```
Router ARP request: "Chi ha 192.168.150.69?"
    │
    ▼
Container risponde con MAC dell'HOST: "192.168.150.69 è 2c:cf:67:b2:47:ea"
    │
    ▼
ARP table del router: 192.168.150.69 → 2c:cf:67:b2:47:ea
ARP table del router: 192.168.0.102  → 2c:cf:67:b2:47:ea
                      (stesso MAC, 2 IP diversi)
```

**Why it matters:**

| Scenario | MacVLAN | IPVLAN |
|---|---|---|
| Switch with port security (max 1 MAC per port) | **Blocked** - the switch sees 2 MACs and disables the port | **Works** - only one MAC visible |
| 802.1X (per-port authentication) | **Blocked** - only the authenticated MAC passes | **Works** - same authenticated MAC |
| Wi-Fi (many APs reject multiple MACs) | **Does not work** | **Works** |
| Cloud/VPS (provider filters unknown MACs) | **Does not work** | **Works** |

> **In our lab**: I chose IPVLAN specifically because some consumer switches implement a basic form of port security that limits MACs per port. With IPVLAN, the switch does not notice any difference - it always sees the same Raspberry Pi MAC, regardless of how many containers are running.
