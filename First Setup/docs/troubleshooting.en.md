>  [Italiano](troubleshooting.md) |  **English**

# Troubleshooting - First setup: real problems and solutions

> Typical problems of the first-install phase (OS, first SSH access, EEPROM, NVMe) and how to solve them. For operational faults that happen **after** the system is in production (kernel panic, lockout, boot that stops working) see the [Incident Recovery / lost access and boot](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.en.md) runbook.

---

## Problem 1: The NVMe is not detected (`lsblk` does not show it)

**Symptom:** after connecting the SSD to the M.2 adapter, `lsblk` does not list `nvme0n1`. The disk seems invisible.

**Cause:** on the Raspberry Pi 5 the causes are almost always four, in order of frequency: insufficient power, a restrictive kernel parameter, an outdated EEPROM, or an incompatible adapter.

**Solution:** diagnose in sequence to isolate the cause.

```bash
# 1. Does the PCIe controller see the device?
lspci -nn | grep -i nvme
#   Nothing -> physical/power problem. Controller present but empty lsblk -> adapter

# 2. What does the kernel say at boot?
dmesg | grep -i nvme
#   "nvme: max host mem = 0" -> restrictive kernel parameter (see below)

# 3. Power: the NVMe increases consumption. With an undersized supply
#    the disk can disappear under load.
vcgencmd get_throttled     # expected 0x0
```

| Cause | Diagnosis | Fix |
|---|---|---|
| Adapter not powered / weak supply | `lspci` shows nothing | Official 27W power supply (5.1V/5A) |
| Restrictive kernel parameter | `dmesg`: `nvme: max host mem = 0` | Remove `nvme.max_host_mem_size_mb=0` from `/boot/firmware/cmdline.txt` |
| Outdated bootloader (EEPROM) | NVMe not supported by boot | Update the EEPROM (`sudo rpi-eeprom-update -a`) |
| Incompatible adapter | `lspci` shows the controller but `lsblk` does not | Try another M.2-to-PCIe adapter |

---

## Problem 2: `cmdline.txt` edited and the system ignores the options

**Symptom:** after editing `/boot/firmware/cmdline.txt`, the options have no effect or the boot behaves strangely.

**Cause:** `cmdline.txt` **must be a single line**. An editor that wraps the line breaks it and the kernel ignores everything after the break.

**Solution:**

```bash
# Verify there are no line-ends ($) in the middle
cat -A /boot/firmware/cmdline.txt
# There must be ONE $ at the end only. A $ in the middle -> broken line, put it back on one line
```

---

## Problem 3: The Pi does not boot from the NVMe (still starts from the SD)

**Symptom:** the NVMe is detected and has a valid OS, but at power-on the Pi always starts from the MicroSD.

**Cause:** the boot order in the EEPROM does not prioritize the NVMe.

**Solution:**

```bash
# Via raspi-config
sudo raspi-config      # Advanced Options -> Boot Order -> NVMe/USB Boot

# Or manually, in the EEPROM
sudo rpi-eeprom-config --edit
# Set: BOOT_ORDER=0xf416   (6=NVMe, 1=SD, 4=USB, f=restart)
#   0xf416 = try NVMe, then SD, then USB
```

> For an in-depth boot diagnosis (EEPROM, chroot, broken `/etc/fstab`), see [Incident Recovery / lost access and boot, Part D](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.en.md).

---

## Problem 4: Instability with forced PCIe Gen 3

**Symptom:** after forcing PCIe Gen 3 mode for more speed, random I/O errors appear, the disk "detaches" under load or the filesystem goes read-only.

**Cause:** the Pi 5 officially certifies PCIe only at **Gen 2**. Forcing Gen 3 (`dtparam=pciex1_gen=3`) works with many SSDs but not all: some adapters/disks are unstable at that frequency.

**Solution:** if I/O errors appear, go back to Gen 2 by removing the `dtparam` from `/boot/firmware/config.txt`. The throughput difference is real but stability on a 24/7 server matters more; the random IOPS (what Wazuh/Docker need) are anyway hugely higher than the SD even at Gen 2.

```bash
# Check the negotiated PCIe link speed
sudo lspci -vv | grep -i "LnkSta:"
```

---

## Problem 5: I can't find the Raspberry's IP for the first SSH

**Symptom:** the Pi is on but you do not know which IP the DHCP assigned it.

**Solution:**

```bash
# From the router's DHCP table, or a LAN scan
nmap -sn 192.168.0.0/24
# Look for the host with vendor "Raspberry Pi". On Windows: arp -a
```

The first boot takes ~60 seconds (filesystem expansion and customizations): if it does not answer immediately, wait before worrying.

---

## Problem 6: "REMOTE HOST IDENTIFICATION HAS CHANGED"

**Symptom:** after an OS reinstall, an SD reflash or a device change on the same IP, SSH refuses the connection with an alarming identity-changed warning.

**Cause:** the host key presented by the server does not match the one saved in `~/.ssh/known_hosts`. It is SSH's anti man-in-the-middle mechanism: it triggers every time the key changes.

**Solution (only if the change is legitimate):**

```bash
# Remove the old entry for that IP
ssh-keygen -R 192.168.0.102
# The next connection will ask to accept the new fingerprint
```

> **Warning:** if you did **not** reinstall anything and you see this warning, stop and investigate: it could be a real MitM or ARP spoofing. See [Incident Recovery / post-downtime integrity, Phase 6](../../Incident%20Recovery%20%26%20Resilience/docs/integrita-post-downtime.en.md).

---

## Problem 7: Random reboots/slowdowns after installation

**Symptom:** the system reboots on its own, is slow for no reason, or shows a lightning bolt on the screen.

**Cause:** under-voltage. With the NVMe connected, consumption rises and a non-official power supply often cannot keep up.

**Solution:**

```bash
vcgencmd get_throttled
# 0x0 = ok. 0x50000/0x50005 = under-voltage (now or in the past) -> official 27W power supply
```

---

## Useful verification commands

```bash
# Where am I booting from? (root on nvme or on mmcblk?)
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|mmcblk|/$"

# EEPROM version and update status
sudo rpi-eeprom-update

# Current boot order
vcgencmd bootloader_config | grep BOOT_ORDER

# System updated with all patches (kernel included)
sudo apt update && sudo apt full-upgrade -y
```

---

## Links

- Post-production operational faults (panic, lockout, recovery from SD) -> [Incident Recovery / lost access and boot](../../Incident%20Recovery%20%26%20Resilience/docs/accesso-perso-e-boot.en.md)
- Storage architecture and migration to NVMe -> [storage-nvme](storage-nvme.en.md)
- First access and SSH fingerprint in detail -> [primo-accesso](primo-accesso.en.md)
- EEPROM update -> [bootloader](bootloader.en.md)
