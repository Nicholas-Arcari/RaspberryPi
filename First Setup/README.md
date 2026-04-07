# First Setup - Installazione e Configurazione Iniziale del Raspberry Pi 5

Questa guida copre tutto il necessario per portare un Raspberry Pi 5 da "scatola appena aperta" a "sistema operativo funzionante con boot da NVMe". Include i problemi reali che ho incontrato e come li ho risolti.

---

## Panoramica

Il Raspberry Pi 5 verra' configurato con:

- **Raspberry Pi OS Lite 64-bit (Bookworm)** come sistema operativo
- **Boot diretto da NVMe SSD** per prestazioni e durabilita'
- **Accesso esclusivamente via SSH** (nessun monitor, tastiera o interfaccia grafica)
- **MicroSD** usata solo per il flash iniziale e come recovery d'emergenza

---

## Perche' Bookworm e NON Trixie

Al momento della stesura, Raspberry Pi OS e' disponibile in due versioni:

| | Bookworm (Debian 12) | Trixie (Debian 13) |
|---|---|---|
| **Stato** | Stable, LTS | Testing/Unstable |
| **Compatibilita' OMV** | Supportato (OMV 7) | **NON supportato** |
| **Compatibilita' Wazuh** | Supportato (4.x) | **NON supportato** |
| **Pacchetti Docker** | Stabili | Possibili breaking changes |
| **Supporto comunita'** | Ampio, documentato | Limitato |

**Regola pratica in cybersecurity:** su un sistema che deve fare da server 24/7, si usa *sempre* la release stable. I pacchetti testing/unstable possono introdurre regressioni che rompono servizi in produzione senza preavviso. Bookworm riceve security patches senza cambiamenti di funzionalita' - esattamente quello che serve.

Inoltre, **va usata la versione Lite (headless)**, senza interfaccia grafica. Motivi:

- OpenMediaVault blocca esplicitamente l'installazione su sistemi con Desktop Environment
- Un server non necessita di GUI - spreca RAM e CPU per nulla
- Meno superficie d'attacco: meno pacchetti installati = meno CVE potenziali

---

## Step 1: Flash del Sistema Operativo

### Strumento: Raspberry Pi Imager

Scaricare Raspberry Pi Imager dalla pagina ufficiale: https://www.raspberrypi.com/software/

#### 1.1 Selezione del dispositivo

Avviare Imager e selezionare **Raspberry Pi 5** come dispositivo target.

![Selezione del dispositivo in Raspberry Pi Imager](img/rpi-imager-device-selection.jpg)

#### 1.2 Selezione del sistema operativo

Selezionare la categoria **Raspberry Pi OS (other)** per accedere alle varianti Lite.

![Selezione della categoria OS](img/rpi-imager-os-selection.jpg)

Selezionare **Raspberry Pi OS Lite (64-bit)** basato su Debian Bookworm. La versione a 64-bit e' essenziale perche':

- Wazuh Indexer (OpenSearch) richiede architettura a 64-bit
- Docker su ARM64 ha un ecosistema di immagini piu' ampio rispetto a armhf (32-bit)
- Il Raspberry Pi 5 ha 8GB di RAM - con un OS a 32-bit ne vedrebbe al massimo 4GB per processo (limite dello spazio di indirizzamento a 32-bit)

![Selezione Raspberry Pi OS Lite 64-bit Bookworm](img/rpi-imager-os-lite.jpg)

#### 1.3 Selezione dello storage

Selezionare la MicroSD come destinazione. Al primo boot il sistema partira' dalla SD, poi migreremo su NVMe.

![Selezione della MicroSD come storage](img/rpi-imager-storage.jpg)

#### 1.4 Personalizzazione (Customisation)

Prima di scrivere, cliccare su **Customisation** e configurare:

- **Hostname**: un nome identificativo (es. `raspberrypi`, `homelab`, `nickpi`)
- **Username e Password**: creare un utente NON-root (es. `pi` con password robusta)
- **Locale/Timezone**: `Europe/Rome`, layout tastiera `it`
- **SSH**: abilitare SSH con autenticazione tramite password (la chiave pubblica la configureremo dopo)
- **Wi-Fi**: NON configurare il Wi-Fi - un server deve usare Ethernet per stabilita' e per MacVLAN

> **Nota di sicurezza:** la password impostata in Imager viene salvata in chiaro nel file `firstrun.sh` sulla SD durante il flash. Dopo il primo boot, il file viene eliminato, ma chiunque abbia accesso fisico alla SD prima del boot puo' leggerla. Se il dispositivo e' in un ambiente condiviso, cambiare la password immediatamente dopo il primo accesso.

#### 1.5 Scrittura

Cliccare **Write** e attendere il completamento. Imager verifica automaticamente l'integrita' della scrittura tramite checksum.

---

## Step 2: Primo Accesso via SSH

Inserire la MicroSD nel Raspberry Pi, collegare il cavo Ethernet e l'alimentazione. Attendere ~60 secondi per il primo boot (il primo avvio e' piu' lento perche' espande il filesystem e applica le customizzazioni).

### Individuare l'IP del Raspberry

Se non conosci l'IP assegnato dal DHCP:

```bash
# Dal router: controllare la tabella DHCP clients
# Oppure, da un altro PC sulla stessa rete:
nmap -sn 192.168.0.0/24
# Oppure, su Windows:
arp -a
```

### Connessione SSH

```bash
ssh pi@<IP_DEL_RASPBERRY>
```

Al primo collegamento, SSH chiedera' di confermare il fingerprint del server:

```
The authenticity of host '192.168.0.102 (192.168.0.102)' can't be established.
ED25519 key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Cosa sta succedendo a livello tecnico:** SSH utilizza il protocollo di scambio chiavi Diffie-Hellman (o la variante ECDH con Curve25519) per stabilire una sessione cifrata. La prima volta che ti connetti, il client non ha mai visto quel server e ti chiede di verificare manualmente il fingerprint - una rappresentazione compressa della chiave pubblica del server (nel formato `SHA256:base64`). Digitando `yes`, il client salva questa associazione `IP → chiave pubblica` nel file `~/.ssh/known_hosts`.

### Il temuto "REMOTE HOST IDENTIFICATION HAS CHANGED"

Se dopo una reinstallazione dell'OS, una reflash della SD o un cambio di dispositivo sullo stesso IP, SSH mostrera':

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
```

**Cosa sta succedendo:** SSH ha confrontato la chiave pubblica presentata dal server con quella salvata in `known_hosts` e ha trovato una discrepanza. Questo e' esattamente il meccanismo che protegge da un attacco **Man-in-the-Middle (MitM)**: se un attaccante si interponesse tra te e il server, presenterebbe una chiave diversa e SSH bloccherebbe la connessione.

Nel nostro caso, sappiamo che il cambio di chiave e' legittimo (abbiamo reinstallato l'OS), quindi possiamo rimuovere la vecchia entry:

```bash
ssh-keygen -R <IP_DEL_RASPBERRY>
```

Questo comando rimuove la riga corrispondente a quell'IP dal file `~/.ssh/known_hosts`. La prossima connessione chiedera' di nuovo di accettare il nuovo fingerprint.

> **Attenzione:** Se non hai reinstallato nulla e vedi questo avviso, **fermati e indaga**. Potrebbe essere un vero attacco MitM, un ARP spoofing sulla rete locale, o un altro dispositivo che ha preso lo stesso IP.

---

## Step 3: Aggiornamento del sistema

Dopo il primo accesso, aggiornare immediatamente tutti i pacchetti:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

**Perche' `full-upgrade` e non `upgrade`:**

- `apt upgrade`: aggiorna solo i pacchetti che non richiedono la rimozione o l'installazione di nuovi pacchetti
- `apt full-upgrade`: aggiorna tutto, anche se richiede di rimuovere pacchetti obsoleti o installarne di nuovi (necessario per aggiornamenti del kernel e delle librerie di sistema)

Su un sistema appena installato, `full-upgrade` garantisce di avere tutte le patch di sicurezza piu' recenti, incluse quelle del kernel.

---

## Step 4: Verifica e aggiornamento del Bootloader (EEPROM)

Il bootloader del Raspberry Pi 5 risiede in una EEPROM (Electrically Erasable Programmable Read-Only Memory) separata dalla SD/NVMe. Questo significa che:

- Il bootloader sopravvive a una formattazione completa del disco
- Puo' essere aggiornato indipendentemente dall'OS
- Un bootloader aggiornato e' necessario per il boot da NVMe (le prime versioni non lo supportavano)

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

Il flag `-a` (apply) scarica e scrive il firmware aggiornato nella EEPROM. Il reboot e' necessario perche' il nuovo bootloader viene attivato solo al prossimo avvio.

> **Nessun rischio:** Se il boot avviene dalla MicroSD, aggiornare l'EEPROM non cambia il metodo di boot. Il Pi continuera' ad avviarsi dalla SD finche' non configureremo esplicitamente il boot da NVMe.

---

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

Prossimo step: [NAS (Network Attached Storage)](../NAS%20(Network%20Attached%20Storage)/) - configurare OpenMediaVault e le condivisioni di rete.
