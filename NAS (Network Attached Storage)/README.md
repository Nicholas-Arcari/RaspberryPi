# NAS - Network Attached Storage con OpenMediaVault 7

Questa sezione documenta la trasformazione del Raspberry Pi 5 in un NAS completo usando OpenMediaVault 7, dalla preparazione del disco NVMe alla configurazione delle condivisioni di rete accessibili da Windows, macOS e Linux.

---

## Teoria: Cos'e' un NAS e perche' OMV

Un NAS (Network Attached Storage) e' un dispositivo di rete dedicato alla condivisione di file. A differenza di un semplice hard disk USB condiviso, un NAS offre:

- **Protocolli di rete standard** (SMB per Windows, NFS per Linux/macOS)
- **Gestione utenti e permessi** (chi puo' leggere, chi puo' scrivere)
- **Monitoraggio salute dei dischi** (SMART)
- **Interfaccia web** per la configurazione

**OpenMediaVault (OMV)** e' una distribuzione NAS open-source basata su Debian. La versione 7 (basata su Bookworm) e' compatibile con ARM64 e si installa sopra un Raspberry Pi OS Lite esistente senza sovrascriverlo. OMV diventa, di fatto, un "layer di gestione" che controlla i servizi di rete, lo storage e i permessi tramite una web UI sulla porta 80.

---

## Indice

| # | Sezione | Descrizione |
|---|---------|-------------|
| 1 | [Preparazione NVMe](docs/preparazione-nvme.md) | Rilevamento disco, verifica kernel, PCIe, cause comuni di mancato rilevamento, pulizia del disco |
| 2 | [Filesystem EXT4](docs/filesystem-ext4.md) | Partizionamento GPT, formattazione EXT4, deep dive journaling modes, mount persistente con fstab |
| 3 | [Installazione OMV](docs/installazione-omv.md) | Prerequisiti, installazione via script ufficiale, accesso alla web UI |
| 4 | [Configurazione OMV](docs/configurazione-omv.md) | Gestione dischi, filesystem, cartelle condivise, SMB/CIFS, NFS, test da Windows e Linux |
| 5 | [Plex Media Server](docs/plex.md) | Installazione Plex, verifica e accesso, consigli di manutenzione |
| 6 | [Alternative e confronti](docs/alternative.md) | RPi come NAS (quando si'/no), RPi vs Synology/QNAP, SBC alternativi, software NAS (OMV vs TrueNAS vs CasaOS vs Unraid), installazione CasaOS |

---

Prossimo step: [Docker & Portainer](../Docker%20%26%20Portainer/) - installare la piattaforma container per tutti i servizi aggiuntivi.
