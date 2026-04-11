>  [English](bootloader.en.md) |  **Italiano**

# Verifica e Aggiornamento del Bootloader (EEPROM)

## Step 4: Verifica e aggiornamento del Bootloader (EEPROM)

Il bootloader del Raspberry Pi 5 risiede in una EEPROM (Electrically Erasable Programmable Read-Only Memory) separata dalla SD/NVMe. Questo significa che:

- Il bootloader sopravvive a una formattazione completa del disco
- Può essere aggiornato indipendentemente dall'OS
- Un bootloader aggiornato è necessario per il boot da NVMe (le prime versioni non lo supportavano)

### Controllare la versione corrente

```bash
sudo rpi-eeprom-update
```

Output tipico:

```
BOOTLOADER: up to date
   CURRENT: Thu 05 Dec 2024 03:08:22 PM UTC (1733410102)
    LATEST: Thu 05 Dec 2024 03:08:22 PM UTC (1733410102)
   RELEASE: default (/lib/firmware/raspberrypi/bootloader-2712/default)
            Use raspi-config to change the release.
```

Se `CURRENT` e `LATEST` differiscono:

```bash
sudo rpi-eeprom-update -a
sudo reboot
```

Il flag `-a` (apply) scarica e scrive il firmware aggiornato nella EEPROM. Il reboot è necessario perchè il nuovo bootloader viene attivato solo al prossimo avvio.

> **Nessun rischio:** Se il boot avviene dalla MicroSD, aggiornare l'EEPROM non cambia il metodo di boot. Il Pi continuerà ad avviarsi dalla SD finchè non configureremo esplicitamente il boot da NVMe.
