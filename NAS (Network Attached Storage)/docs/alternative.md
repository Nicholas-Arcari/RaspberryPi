>  [English](alternative.en.md) |  **Italiano**

# Ha senso un Raspberry Pi come NAS? Quando sì e quando no

Questa è la prima domanda da farsi. La risposta onesta: **dipende dal carico di lavoro**.

## Quando il Raspberry Pi come NAS ha senso

- **Home lab educativo** (il nostro caso): vuoi imparare Linux, Docker, SIEM, networking. Il Pi costa 80-100 EUR ed è sufficiente
- **Archivio personale leggero**: foto, documenti, backup periodici. 1-3 utenti simultanei
- **Media server per uso singolo**: Plex/Jellyfin per 1-2 stream simultanei (il Pi5 gestisce transcoding H.264 hardware)
- **Budget limitato**: un NAS Synology 2-bay parte da 300+ EUR senza dischi

## Quando NON ha senso

- **Più di 5 utenti simultanei**: il bus USB3/PCIe del Pi satura (~500 MB/s teorici, ~400 MB/s reali)
- **RAID/Ridondanza dati**: il Pi ha un solo slot PCIe - non puoi fare RAID senza hub USB (che aggiunge un collo di bottiglia)
- **Carichi I/O pesanti 24/7**: database, virtual machine, surveillance con 10+ telecamere
- **Affidabilità enterprise**: il Pi non ha ECC RAM, non ha alimentazione ridondante, un power failure può corrompere il filesystem

## Confronto: Raspberry Pi vs NAS dedicati vs Mini-PC

| | RPi 5 (8GB) | Synology DS224+ | QNAP TS-233 | Mini-PC x86 (N100) |
|---|---|---|---|---|
| **Prezzo (solo unità)** | ~80 EUR | ~350 EUR | ~250 EUR | ~150 EUR |
| **CPU** | Cortex-A76 4-core | Celeron J4125 4-core | Cortex-A55 4-core | Intel N100 4-core |
| **RAM** | 8GB LPDDR4X | 2GB DDR4 (exp. 6GB) | 2GB DDR4 | 8-16GB DDR5 |
| **Slot disco** | 1x PCIe + 1x microSD | 2x SATA 3.5" | 2x SATA 3.5" | 1x NVMe + 2x SATA |
| **RAID** | No (singolo disco) | RAID 1 (mirror) | RAID 1 | RAID 1 (con 2 SATA) |
| **Rete** | 1x Gigabit | 1x Gigabit | 1x 2.5GbE | 1-2x 2.5GbE |
| **Consumo** | 5-8W | 15-20W | 10-15W | 15-25W |
| **Docker** | Si (ARM64) | Si (x86) | Si (ARM64) | Si (x86) |
| **Wazuh** | Si (manuale) | Difficile (risorse limitate) | No (2GB RAM) | **Si** (setup standard) |
| **Software NAS** | OMV, CasaOS | Synology DSM (proprietario) | QNAP QTS (proprietario) | OMV, TrueNAS, Unraid |

> **La mia conclusione:** Per il progetto specifico di questo lab (NAS + SIEM + Honeypot + VPN), il Raspberry Pi 5 8GB è al **limite**. Se dovessi rifare il progetto con budget leggermente superiore, prenderei un mini-PC x86 con N100 (o N200): stessa fascia di prezzo del Pi + alimentatore + case + NVMe, ma con architettura x86 supportata nativamente da tutto (Wazuh, Splunk, Docker immagini standard), più RAM espandibile, e 2.5GbE.

## Alternative al Raspberry Pi: altri SBC (Single Board Computer)

| SBC | CPU | RAM | Storage | Prezzo | Pro | Contro |
|---|---|---|---|---|---|---|
| **Orange Pi 5 Plus** | RK3588 (8-core, 4x A76 + 4x A55) | 8-32GB | 2x NVMe M.2 | ~120 EUR | Due slot NVMe (RAID software possibile), 2x 2.5GbE | Software meno maturo, community più piccola |
| **ODROID H4 Plus** | Intel N97 (x86, 4-core) | 32GB DDR5 | 2x NVMe + 2x SATA | ~150 EUR | **x86 nativo**, supporto perfetto Docker/Wazuh | Non è un SBC ARM (più simile a un mini-PC) |
| **Rock Pi 5B** | RK3588 | 8-16GB | 1x NVMe + eMMC | ~100 EUR | Buona potenza, NPU per AI | Supporto Linux ancora in maturazione |
| **Banana Pi BPI-R4** | MediaTek MT7988A | 4GB | eMMC + microSD | ~100 EUR | 2x 2.5GbE + Wi-Fi 7, pensato come router | RAM limitata per SIEM |

> **Domanda da farsi:** "Ho bisogno di ARM o di x86?" Se il progetto è puramente educativo su ARM e vuoi affrontare le sfide di compatibilità, il Pi è perfetto. Se vuoi che tutto funzioni al primo colpo, un ODROID H4 (x86) elimina il 90% dei problemi documentati in questa repo.

## Alternative a OpenMediaVault: altri software NAS

| Software | Base | Filesystem | Licenza | RPi 5 | Caratteristica unica |
|---|---|---|---|---|---|
| **OpenMediaVault 7** | Debian 12 | EXT4, Btrfs, XFS | GPLv3 | **Si** | Plugin ecosystem, integrazione Debian nativa |
| **TrueNAS Scale** | Debian 12 | **OpenZFS** | BSD | No (solo x86) | ZFS: snapshot, dedup, self-healing, RAIDZ |
| **TrueNAS Core** | FreeBSD | OpenZFS | BSD | No (solo x86) | Stabilità FreeBSD, bhyve VMs |
| **CasaOS** | Qualsiasi Linux | Qualsiasi | Apache 2.0 | **Si** | UI moderna, app store one-click, leggero |
| **Unraid** | Slackware | XFS + Btrfs (cache) | Proprietario ($59+) | No (solo x86) | Array parity senza RAID tradizionale, Docker/VM |

### CasaOS: alternativa leggera per chi vuole semplicità

Se il tuo obiettivo è solo un NAS con Docker e un'interfaccia bella, CasaOS è molto più leggero di OMV:

```bash
# Installazione CasaOS (una riga)
curl -fsSL https://get.casaos.io | sudo bash

# Dopo l'installazione, accedi su http://<IP>:80
# App store integrato: Pi-hole, Portainer, Jellyfin, Nextcloud in un click
```

| | OMV 7 | CasaOS |
|---|---|---|
| **Complessità setup** | Media (script + configurazione) | Bassa (un comando) |
| **Gestione disco** | Completa (RAID, SMART, filesystem) | Base (mount e condivisione) |
| **Plugin** | Ampio ecosistema | App store Docker-based |
| **Risorse** | ~200MB RAM | ~80MB RAM |
| **Conflitti con Docker** | Possibili (porta 80, systemd) | Nessuno (Docker-native) |
| **Per il nostro progetto** | **Scelto** (gestione disco avanzata) | Alternativa valida se non serve SMART/RAID |

> **Perchè ho scelto OMV e non CasaOS:** OMV offre gestione disco di livello enterprise (SMART monitoring, scheduler I/O, filesystem tuning, ACL granulari). CasaOS è più user-friendly ma manca di queste funzionalità. Per un lab di sicurezza dove il disco lavora pesantemente (log SIEM, indici OpenSearch), il controllo offerto da OMV è necessario.
