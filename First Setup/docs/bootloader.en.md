>  [Italiano](bootloader.md) |  **English**

# Bootloader (EEPROM) Verification and Update

## Step 4: Bootloader (EEPROM) Verification and Update

The Raspberry Pi 5's bootloader resides in a separate EEPROM (Electrically Erasable Programmable Read-Only Memory) from the SD/NVMe. This means that:

- The bootloader survives a complete disk format
- It can be updated independently from the OS
- An updated bootloader is required for NVMe boot (early versions did not support it)

### Checking the Current Version

```bash
sudo rpi-eeprom-update
```

Typical output:

```
BOOTLOADER: up to date
   CURRENT: Thu 05 Dec 2024 03:08:22 PM UTC (1733410102)
    LATEST: Thu 05 Dec 2024 03:08:22 PM UTC (1733410102)
   RELEASE: default (/lib/firmware/raspberrypi/bootloader-2712/default)
            Use raspi-config to change the release.
```

If `CURRENT` and `LATEST` differ:

```bash
sudo rpi-eeprom-update -a
sudo reboot
```

The `-a` flag (apply) downloads and writes the updated firmware to the EEPROM. The reboot is necessary because the new bootloader is only activated on the next startup.

> **No risk involved:** If boot is occurring from the MicroSD, updating the EEPROM does not change the boot method. The Pi will continue to boot from the SD until we explicitly configure NVMe boot.
