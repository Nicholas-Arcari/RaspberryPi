>  [Italiano](teoria-vlan.md) |  **English**

# Theory: Why Segment the Network

In a security home lab, all services (NAS, Honeypot, Pi-hole, SIEM) run on the same physical device. Without network segmentation, an attacker who compromises the Honeypot container could potentially reach the NAS and personal data.

Network segmentation creates **logical boundaries** between services, even though they physically share the same Raspberry Pi and the same Ethernet cable.

---

## VLAN Tagging (IEEE 802.1Q)

A **VLAN (Virtual LAN)** is a separate logical network that shares the same physical infrastructure. The **IEEE 802.1Q** protocol adds a **4-byte tag** to the Ethernet frame header that identifies the VLAN membership:

```
[MAC dst] [MAC src] [802.1Q Tag: VLAN ID 150] [EtherType] [Payload] [FCS]
                     └── 4 byte inseriti ──┘
```

The tag contains:

- **TPID** (Tag Protocol Identifier): `0x8100` - identifies the frame as tagged
- **PCP** (Priority Code Point): 3 bits for QoS (traffic priority)
- **DEI** (Drop Eligible Indicator): 1 bit
- **VID** (VLAN Identifier): 12 bits → supports up to 4094 VLANs (0 and 4095 are reserved)

### Switch Ports: Access vs Trunk

| Port Type | Behavior | Typical Use |
|---|---|---|
| **Access** | Carries traffic for a single VLAN, untagged | PCs, printers, end devices |
| **Trunk** | Carries traffic for multiple VLANs, with 802.1Q tags | Connections between switches, multi-VLAN servers |

**For our setup:** The switch port to which the Raspberry Pi is connected must be configured as **Trunk** (or with VLAN 150 as "tagged"). If the switch is **unmanaged**, this configuration **will not work** because the switch will drop tagged frames.
