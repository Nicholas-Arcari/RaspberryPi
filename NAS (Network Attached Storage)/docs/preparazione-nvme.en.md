>  [Italiano](preparazione-nvme.md) |  **English**

# Step 1: NVMe Detection and Preparation

## Verify that the kernel detects the disk

```bash
lsblk
```

Expected output:

```
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
mmcblk0     179:0    0  58.3G  0 disk           ← MicroSD
├─mmcblk0p1 179:1    0   512M  0 part /boot/firmware
└─mmcblk0p2 179:2    0  57.8G  0 part /
nvme0n1     259:0    0 238.5G  0 disk           ← NVMe SSD
```

If the NVMe **does not appear**, check the following in order:

```bash
# Verify that the PCIe controller detects the device
lspci -nn | grep -i nvme

# Check kernel messages during boot
dmesg | grep -i nvme
```

## Common causes of detection failure

| Problem | Diagnostics | Solution |
|---|---|---|
| Adapter not powered | `lspci` shows nothing | Use the official 27W power supply |
| Restrictive kernel parameter | `dmesg` shows `nvme: max host mem = 0` | Remove `nvme.max_host_mem_size_mb=0` from `/boot/firmware/cmdline.txt` |
| Outdated bootloader | NVMe not supported | Update EEPROM (see First Setup, Step 4) |
| Incompatible adapter | `lspci` shows the controller but `lsblk` does not show the disk | Try a different M.2-to-PCIe adapter |

> **Warning about `/boot/firmware/cmdline.txt`:** This file must be a **single line** with no line breaks. If you add a newline, the kernel ignores everything after it. After editing, verify with `cat -A /boot/firmware/cmdline.txt` that there are no `$` (end-of-line markers) in the middle.

## Disk wiping

If the disk contains previous partitions or filesystems, they need to be removed:

```bash
# Show signatures present on the disk
sudo wipefs /dev/nvme0n1

# Remove ALL signatures (partition table, filesystem magic bytes)
sudo wipefs -a /dev/nvme0n1
```

**What `wipefs` does:** It does not erase data but removes the "magic bytes" - byte sequences at known disk positions that the kernel uses to identify filesystems and partition tables. Without these markers, the disk appears empty to the system.

> **CRITICAL:** Do not run `wipefs` on the disk you are booting from (`mmcblk0`). If you are booting from NVMe, do not run it on the active NVMe. Always check with `lsblk` before proceeding.
