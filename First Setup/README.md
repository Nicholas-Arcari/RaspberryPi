>  [English](README.en.md) |  **Italiano**

# First Setup - Installazione e Configurazione Iniziale del Raspberry Pi 5

Questa guida copre tutto il necessario per portare un Raspberry Pi 5 da "scatola appena aperta" a "sistema operativo funzionante con boot da NVMe". Include i problemi reali che ho incontrato e come li ho risolti.

---

## Indice

1. [Installazione del Sistema Operativo](docs/installazione-os.md) - Panoramica, scelta di Bookworm, flash con Raspberry Pi Imager
2. [Primo Accesso e Aggiornamento](docs/primo-accesso.md) - Connessione SSH, risoluzione problemi fingerprint, aggiornamento pacchetti
3. [Bootloader (EEPROM)](docs/bootloader.md) - Verifica e aggiornamento del firmware bootloader
4. [Storage NVMe](docs/storage-nvme.md) - Architettura storage, migrazione da MicroSD a NVMe, checklist finale
5. [Troubleshooting](docs/troubleshooting.md) - NVMe non rilevato, cmdline.txt, boot order, PCIe Gen 3, fingerprint SSH, under-voltage

---

Prossimo step: [NAS (Network Attached Storage)](../NAS%20(Network%20Attached%20Storage)/) - configurare OpenMediaVault e le condivisioni di rete.
