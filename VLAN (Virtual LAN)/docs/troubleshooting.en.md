>  [Italiano](troubleshooting.md) |  **English**

# Limitations and Troubleshooting

## 1. The Host Cannot Communicate with IPVLAN/MacVLAN Containers

This is **by design**. The Linux kernel prevents communication between the parent interface and IPVLAN/MacVLAN sub-interfaces for security reasons (internal ARP spoofing prevention).

**Practical consequence:** The Raspberry Pi (192.168.0.102) will not be able to ping Pi-hole (192.168.150.69). All **other** devices on the network (PCs, smartphones, router) will be able to reach it normally.

**Workaround (if needed):** Create a MacVLAN interface on the host connected to the same network:

```bash
sudo ip link add mvl0 link end0.150 type macvlan mode bridge
sudo ip addr add 192.168.150.100/24 dev mvl0
sudo ip link set mvl0 up
```

## 2. The Container Does Not Respond to Ping from Other Devices

Diagnostic checklist:

| Check | Command | What to Look For |
|---|---|---|
| Does the VLAN interface exist? | `ip a \| grep end0.150` | Must show UP state |
| Does the Docker network exist? | `docker network ls` | `ipvlan_150` must be present |
| Is the container on the correct network? | `docker inspect pihole \| grep NetworkMode` | Must show `ipvlan_150` |
| Does the switch accept the VLAN tag? | Check switch configuration | Port must be Trunk or Tagged VLAN 150 |

## 3. Unmanaged Switch

If your switch is a consumer model without a management interface, it **does not support VLAN tagging**. Frames with 802.1Q tags will be silently dropped or, in some cases, passed through but ignored by the destination device.

**Solution:** Use IPVLAN **without** VLAN tagging (directly on the physical interface `end0`):

```bash
docker network create -d ipvlan \
    --subnet=192.168.0.0/24 \
    --gateway=192.168.0.1 \
    -o parent=end0 \
    -o ipvlan_mode=l2 \
    ipvlan_flat
```

You lose VLAN isolation, but you keep the advantages of IPVLAN (dedicated IP, no NAT, real client IP visibility).
