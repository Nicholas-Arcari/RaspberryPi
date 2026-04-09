# Step 1: Rilevamento e Preparazione dell'NVMe

## Verifica che il kernel rilevi il disco

```bash
lsblk
```

Output atteso:

```
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
mmcblk0     179:0    0  58.3G  0 disk           ← MicroSD
├─mmcblk0p1 179:1    0   512M  0 part /boot/firmware
└─mmcblk0p2 179:2    0  57.8G  0 part /
nvme0n1     259:0    0 238.5G  0 disk           ← NVMe SSD
```

Se l'NVMe **non appare**, verificare in sequenza:

```bash
# Verifica che il controller PCIe rilevi il dispositivo
lspci -nn | grep -i nvme

# Controlla i messaggi del kernel durante il boot
dmesg | grep -i nvme
```

## Cause comuni di mancato rilevamento

| Problema | Diagnostica | Soluzione |
|---|---|---|
| Adattatore non alimentato | `lspci` non mostra nulla | Usare alimentatore ufficiale 27W |
| Parametro kernel restrittivo | `dmesg` mostra `nvme: max host mem = 0` | Rimuovere `nvme.max_host_mem_size_mb=0` da `/boot/firmware/cmdline.txt` |
| Bootloader vecchio | NVMe non supportato | Aggiornare EEPROM (vedi First Setup, Step 4) |
| Adattatore incompatibile | `lspci` mostra il controller ma `lsblk` non mostra il disco | Provare un altro adattatore M.2-to-PCIe |

> **Attenzione a `/boot/firmware/cmdline.txt`:** Questo file deve essere una **singola riga** senza interruzioni. Se vai a capo, il kernel ignora tutto quello che segue. Dopo la modifica, verificare con `cat -A /boot/firmware/cmdline.txt` che non ci siano `$` (fine riga) nel mezzo.

## Pulizia del disco

Se il disco contiene partizioni o filesystem precedenti, vanno rimossi:

```bash
# Mostra le signature presenti sul disco
sudo wipefs /dev/nvme0n1

# Rimuove TUTTE le signature (partition table, filesystem magic bytes)
sudo wipefs -a /dev/nvme0n1
```

**Cosa fa `wipefs`:** Non cancella i dati ma rimuove i "magic bytes" - sequenze di byte in posizioni note del disco che il kernel usa per identificare filesystem e tabelle delle partizioni. Senza questi marker, il disco appare vuoto al sistema.

> **CRITICO:** Non eseguire `wipefs` sul disco da cui stai facendo boot (`mmcblk0`). Se hai boot da NVMe, non eseguirlo sull'NVMe attivo. Controlla sempre con `lsblk` prima di procedere.
