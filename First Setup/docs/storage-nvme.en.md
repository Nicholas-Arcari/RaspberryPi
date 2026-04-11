>  [Italiano](storage-nvme.md) |  **English**

# Storage Architecture - Why NVMe

## Step 5: Storage Architecture - Why NVMe

### The MicroSD Problem

MicroSD cards are designed for sequential read workloads (cameras, media players). A security server generates very different workloads:

- **SIEM Logs**: Wazuh writes thousands of JSON events per second to disk
- **OpenSearch Database**: the Indexer maintains on-disk indices with high-frequency random writes
- **Docker layers**: image pulls, container creation, volumes - all random I/O
- **PCAP**: if packet capture is enabled, this means GB/day of writes

MicroSD NAND cells have a finite number of write cycles (typically 3,000-10,000 for consumer-grade). With the workloads described, an SD card wears out in a few months, causing first slowdowns and then filesystem corruption.

### The Solution: NVMe SSD

An NVMe SSD connected via PCIe offers:

| Feature | MicroSD (A2 U3) | NVMe SSD (PCIe Gen 3x4) |
|---|---|---|
| Sequential read | ~100 MB/s | ~2,000-3,500 MB/s |
| Sequential write | ~60 MB/s | ~1,000-2,000 MB/s |
| Random 4K IOPS | ~4,000 | ~100,000-500,000 |
| Endurance (TBW) | Not specified | 100-600 TBW |
| Wear leveling | Basic | Advanced with dedicated controller |

> **The Raspberry Pi 5 has a PCIe 2.0 x1 bus**, so effective speeds will be limited to ~400-500 MB/s sequential. However, the advantage in random IOPS remains enormous and the endurance is incomparably superior.

### Two Migration Strategies

#### Option A - Docker Root Directory on NVMe (Recommended to Start)

The operating system stays on the MicroSD, but all Docker data (images, containers, volumes, logs) is moved to the NVMe.

Advantages:
- Simplicity: if something goes wrong, just remove the SD and reflash it
- The OS on the SD has minimal I/O load (only boot and system commands)
- All the heavy workload (SIEM, Honeypot, VPN) runs on the NVMe

To implement this option, after installing Docker (Docker & Portainer section), modify `/etc/docker/daemon.json`:

```json
{
  "data-root": "/mnt/nvme/docker"
}
```

#### Option B - Direct NVMe Boot (Pro)

The operating system is cloned or installed directly on the NVMe. The MicroSD is no longer needed for boot.

Advantages:
- Maximum performance for the entire system
- A single storage point to manage
- No risk of SD wear

Requirements:
- Updated EEPROM bootloader (Step 4)
- Boot order configuration via `raspi-config` or direct EEPROM modification:

```bash
sudo raspi-config
# Advanced Options -> Boot Order -> NVMe/USB Boot
```

Or manually:

```bash
sudo rpi-eeprom-config --edit
# Set: BOOT_ORDER=0xf416
# 6=NVMe, 1=SD, 4=USB, f=restart
```

The order `0xf416` means: try NVMe first, then SD, then USB. If none has a valid OS, restart from the beginning.

> **My choice:** I opted for Option B (NVMe boot). The main reason is that Wazuh Indexer generates such a high volume of I/O that even having only the OS on the SD caused slowdowns during log ingestion peaks. With everything on NVMe, the system is stable and responsive even under load.

---

## Final Checklist

After completing these steps, the Raspberry Pi should be:

- [x] Booted with Raspberry Pi OS Lite 64-bit (Bookworm)
- [x] Accessible via SSH
- [x] System fully updated
- [x] EEPROM bootloader updated
- [x] NVMe storage configured (or planned)

Next step: [NAS (Network Attached Storage)](../../NAS%20(Network%20Attached%20Storage)/README.en.md) - setting up OpenMediaVault and network shares.
