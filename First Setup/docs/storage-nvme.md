# Architettura dello Storage - Perche' NVMe

## Step 5: Architettura dello Storage - Perche' NVMe

### Il problema della MicroSD

Le MicroSD sono progettate per carichi di lavoro in lettura sequenziale (fotocamere, media player). Un server di sicurezza genera carichi molto diversi:

- **Log SIEM**: Wazuh scrive migliaia di eventi JSON al secondo su disco
- **Database OpenSearch**: l'Indexer mantiene indici su disco con scritture random ad alta frequenza
- **Docker layers**: pull di immagini, creazione di container, volumi - tutto I/O random
- **PCAP**: se si abilita la cattura di pacchetti, si parla di GB/giorno di scritture

Le celle NAND delle MicroSD hanno un numero finito di cicli di scrittura (tipicamente 3.000-10.000 per consumer-grade). Con i carichi descritti, una SD si usura in pochi mesi, causando prima rallentamenti e poi corruzione del filesystem.

### La soluzione: NVMe SSD

Un SSD NVMe collegato via PCIe offre:

| Caratteristica | MicroSD (A2 U3) | NVMe SSD (PCIe Gen 3x4) |
|---|---|---|
| Lettura sequenziale | ~100 MB/s | ~2.000-3.500 MB/s |
| Scrittura sequenziale | ~60 MB/s | ~1.000-2.000 MB/s |
| IOPS random 4K | ~4.000 | ~100.000-500.000 |
| Endurance (TBW) | Non specificata | 100-600 TBW |
| Wear leveling | Base | Avanzato con controller dedicato |

> **Il Raspberry Pi 5 ha un bus PCIe 2.0 x1**, quindi le velocita' effettive saranno limitate a ~400-500 MB/s sequenziali. Tuttavia, il vantaggio sulle IOPS random resta enorme e l'endurance e' incomparabilmente superiore.

### Due strategie di migrazione

#### Opzione A - Docker Root Directory su NVMe (Consigliata per iniziare)

Il sistema operativo resta sulla MicroSD, ma tutti i dati Docker (immagini, container, volumi, log) vengono spostati sull'NVMe.

Vantaggi:
- Semplicita': se qualcosa va storto, basta togliere la SD e riflasharla
- L'OS sulla SD ha un carico I/O minimo (solo boot e comandi di sistema)
- Tutto il carico pesante (SIEM, Honeypot, VPN) gira sull'NVMe

Per implementare questa opzione, dopo aver installato Docker (sezione Docker & Portainer), si modifica `/etc/docker/daemon.json`:

```json
{
  "data-root": "/mnt/nvme/docker"
}
```

#### Opzione B - Boot diretto da NVMe (Pro)

Il sistema operativo viene clonato o installato direttamente sull'NVMe. La MicroSD non serve piu' per il boot.

Vantaggi:
- Prestazioni massime per tutto il sistema
- Un solo punto di storage da gestire
- Nessun rischio di usura SD

Richiede:
- Bootloader EEPROM aggiornato (Step 4)
- Configurazione dell'ordine di boot via `raspi-config` o modifica diretta dell'EEPROM:

```bash
sudo raspi-config
# Advanced Options → Boot Order → NVMe/USB Boot
```

Oppure manualmente:

```bash
sudo rpi-eeprom-config --edit
# Impostare: BOOT_ORDER=0xf416
# 6=NVMe, 1=SD, 4=USB, f=restart
```

L'ordine `0xf416` significa: prova prima NVMe, poi SD, poi USB. Se nessuno ha un OS valido, riparti dall'inizio.

> **La mia scelta:** Ho optato per l'Opzione B (boot da NVMe). Il motivo principale e' che Wazuh Indexer genera un volume di I/O talmente elevato che anche avere solo l'OS sulla SD causava rallentamenti durante i picchi di ingestione log. Con tutto su NVMe, il sistema e' stabile e reattivo anche sotto carico.

---

## Checklist finale

Dopo aver completato questi step, il Raspberry Pi dovrebbe essere:

- [x] Avviato con Raspberry Pi OS Lite 64-bit (Bookworm)
- [x] Accessibile via SSH
- [x] Sistema completamente aggiornato
- [x] Bootloader EEPROM aggiornato
- [x] Storage NVMe configurato (o pianificato)

Prossimo step: [NAS (Network Attached Storage)](../../NAS%20(Network%20Attached%20Storage)/) - configurare OpenMediaVault e le condivisioni di rete.
