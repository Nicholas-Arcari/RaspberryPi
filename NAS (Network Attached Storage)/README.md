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

## Step 1: Rilevamento e Preparazione dell'NVMe

### Verifica che il kernel rilevi il disco

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

### Cause comuni di mancato rilevamento

| Problema | Diagnostica | Soluzione |
|---|---|---|
| Adattatore non alimentato | `lspci` non mostra nulla | Usare alimentatore ufficiale 27W |
| Parametro kernel restrittivo | `dmesg` mostra `nvme: max host mem = 0` | Rimuovere `nvme.max_host_mem_size_mb=0` da `/boot/firmware/cmdline.txt` |
| Bootloader vecchio | NVMe non supportato | Aggiornare EEPROM (vedi First Setup, Step 4) |
| Adattatore incompatibile | `lspci` mostra il controller ma `lsblk` non mostra il disco | Provare un altro adattatore M.2-to-PCIe |

> **Attenzione a `/boot/firmware/cmdline.txt`:** Questo file deve essere una **singola riga** senza interruzioni. Se vai a capo, il kernel ignora tutto quello che segue. Dopo la modifica, verificare con `cat -A /boot/firmware/cmdline.txt` che non ci siano `$` (fine riga) nel mezzo.

### Pulizia del disco

Se il disco contiene partizioni o filesystem precedenti, vanno rimossi:

```bash
# Mostra le signature presenti sul disco
sudo wipefs /dev/nvme0n1

# Rimuove TUTTE le signature (partition table, filesystem magic bytes)
sudo wipefs -a /dev/nvme0n1
```

**Cosa fa `wipefs`:** Non cancella i dati ma rimuove i "magic bytes" - sequenze di byte in posizioni note del disco che il kernel usa per identificare filesystem e tabelle delle partizioni. Senza questi marker, il disco appare vuoto al sistema.

> **CRITICO:** Non eseguire `wipefs` sul disco da cui stai facendo boot (`mmcblk0`). Se hai boot da NVMe, non eseguirlo sull'NVMe attivo. Controlla sempre con `lsblk` prima di procedere.

---

## Step 2: Creazione Partizioni e Filesystem

### Partizionamento con GPT

```bash
# Crea una nuova tabella delle partizioni GPT
sudo parted /dev/nvme0n1 mklabel gpt

# Crea una singola partizione che occupa tutto il disco
sudo parted -a optimal /dev/nvme0n1 mkpart primary ext4 0% 100%
```

**Perche' GPT e non MBR:**
- GPT (GUID Partition Table) supporta dischi > 2TB e fino a 128 partizioni
- MBR (Master Boot Record) e' limitato a 2TB e 4 partizioni primarie
- GPT include un CRC32 di backup che protegge dalla corruzione della tabella delle partizioni
- Il bootloader del RPi5 usa GPT nativamente

### Formattazione EXT4

```bash
sudo mkfs.ext4 /dev/nvme0n1p1
```

**Perche' EXT4 e non altri filesystem:**

| Filesystem | Pro | Contro | Verdetto per RPi NAS |
|---|---|---|---|
| **EXT4** | Maturo, stabile, basso overhead, ottimo supporto Linux | No checksum dati, no snapshot nativi | **Scelta consigliata** - affidabile e leggero per ARM |
| **Btrfs** | Snapshot, checksum, compressione, RAID nativo | Overhead CPU significativo, fragile su crash con RAID5/6 | Troppo pesante per RPi5 |
| **XFS** | Eccellente per file grandi, scalabilita' | Non puo' essere ridimensionato verso il basso | Overkill per un NAS domestico |
| **ZFS** | Enterprise-grade, self-healing, RAID-Z | Richiede almeno 8GB RAM solo per ZFS, non nativo nel kernel | Impossibile su RPi5 |

EXT4 con journaling (abilitato di default) offre il miglior compromesso tra affidabilita', performance e consumo di risorse su hardware ARM embedded.

### Deep Dive: EXT4 Journaling Modes

Il journal di EXT4 e' un'area riservata del disco dove le operazioni di scrittura vengono registrate **prima** di essere applicate al filesystem. Se il sistema crasha durante una scrittura, al riavvio il journal viene "replayed" per completare o annullare le operazioni incomplete.

EXT4 supporta tre modalita' di journaling:

| Modalita' | Cosa logga | Performance | Sicurezza dati |
|---|---|---|---|
| `journal` | Metadati + dati | Lenta (ogni byte scritto 2 volte) | Massima - nessuna perdita dati su crash |
| `ordered` (default) | Solo metadati, ma forza l'ordine di scrittura | Buona | Alta - i dati vengono scritti prima dei metadati |
| `writeback` | Solo metadati, nessun ordine garantito | Massima | Bassa - su crash i file possono contenere vecchi dati |

**`ordered`** e' il default e il miglior compromesso: i dati del file vengono scritti su disco **prima** che i metadati (puntatori ai blocchi) vengano aggiornati nel journal. Questo garantisce che se il sistema crasha, i metadati puntano sempre a dati validi (anche se incompleti).

Per verificare la modalita' corrente:

```bash
cat /proc/mounts | grep nvme
# Output: /dev/nvme0n1p1 /srv/dev-disk-by-uuid/xxx ext4 rw,relatime 0 0

sudo tune2fs -l /dev/nvme0n1p1 | grep "Default mount options"
# Output: Default mount options: user_xattr acl
```

### Mount persistente con fstab

OMV gestisce automaticamente `/etc/fstab`, ma e' utile capire la struttura:

```bash
# Formato: <device>  <mount_point>  <type>  <options>  <dump>  <pass>
UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890  /srv/dev-disk-by-uuid/a1b2c3d4-e5f6-7890-abcd-ef1234567890  ext4  defaults,nofail,user_xattr,usrjquota=aquota.user,grpjquota=aquota.group,jqfmt=vfsv0,acl  0  2
```

**Opzioni di mount rilevanti:**

| Opzione | Significato |
|---|---|
| `defaults` | `rw,suid,dev,exec,auto,nouser,async` - permessi standard |
| `nofail` | Se il disco non e' presente al boot, il sistema avvia comunque (evita boot failure se l'NVMe si scollega) |
| `noatime` | Non aggiorna il timestamp di ultimo accesso ad ogni lettura - riduce le scritture del 30-40% (consigliato per SSD) |
| `user_xattr` | Abilita gli extended attributes - necessario per ACL e SELinux |
| `acl` | Abilita le Access Control Lists POSIX |
| `usrjquota` / `grpjquota` | Abilita le quote disco per utente/gruppo (OMV le usa per limitare lo spazio) |

> **Tip per SSD:** Se gestisci fstab manualmente, aggiungi `noatime` per ridurre le scritture. Su un NAS con migliaia di file letti continuamente, `atime` genera scritture inutili ad ogni accesso in lettura. OMV non lo abilita di default.

> **Nota:** Se preferisci, puoi saltare questo step e lasciare che OMV gestisca la formattazione dalla web UI. Il risultato e' identico, ma farlo da CLI ti da' piu' controllo sui parametri.

---

## Step 3: Installazione di OpenMediaVault

### Prerequisiti

- Raspberry Pi OS **Lite** (senza Desktop). OMV blocca l'installazione su sistemi con GUI
- Sistema aggiornato (`sudo apt update && sudo apt full-upgrade -y`)

### Installazione via script ufficiale

```bash
wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash
```

**Cosa fa lo script:**

1. Aggiunge i repository APT di OpenMediaVault
2. Installa i pacchetti core: `openmediavault`, `openmediavault-keyring`
3. Configura i servizi di sistema: nginx (web server), PHP-FPM, monit
4. Imposta la porta 80 per la web UI
5. Crea l'utente admin con password di default

L'installazione richiede 10-20 minuti su RPi5. Non interrompere il processo.

### Accesso alla Web UI

Dopo il reboot:

```bash
http://<IP_DEL_RASPBERRY>:80
```

Credenziali di default:

| Campo | Valore |
|---|---|
| Username | `admin` |
| Password | `openmediavault` |

> **Primo passo obbligatorio:** Cambiare la password admin immediatamente. Vai su **User Settings** (icona ingranaggio in alto a destra) e aggiorna la password. Chiunque sulla tua rete locale puo' accedere alla porta 80 senza autenticazione pregressa.

---

## Step 4: Configurazione OMV - Passo per Passo

### 4.1 Gestione Dischi

Vai su **Storage → Disks**. Qui vedrai tutti i dispositivi di storage rilevati dal kernel.

![OMV - Vista dei dischi collegati: MicroSD da 58GB e NVMe Patriot P320 da 238GB](img/omv-disks.jpg)

Nell'immagine si vede:
- `/dev/mmcblk0` - la MicroSD da 58.30 GiB (boot)
- `/dev/nvme0n1` - l'NVMe Patriot M.2 P320 256GB (storage NAS)

Da questa vista puoi anche controllare lo stato **SMART** del disco cliccando sull'icona dell'ingranaggio. SMART (Self-Monitoring, Analysis and Reporting Technology) e' un sistema di diagnostica integrato in ogni SSD/HDD che monitora parametri come:

- **Temperature**: un NVMe in un case chiuso puo' surriscaldarsi - sopra i 70C le prestazioni calano (thermal throttling)
- **Percentage Used**: indica quanta vita residua ha l'SSD basandosi sui cicli di scrittura consumati
- **Media Errors**: errori non correggibili nella NAND - se questo numero cresce, il disco sta morendo

### 4.2 Gestione Filesystem

Vai su **Storage → File Systems**. Se hai formattato il disco da CLI (Step 2), vedrai la partizione EXT4 gia' presente. Altrimenti, puoi crearla da qui.

![OMV - Gestione filesystem: partizioni montate e disponibili](img/omv-filesystems.jpg)

Seleziona la partizione NVMe e clicca **Mount**. OMV aggiungera' automaticamente l'entry in `/etc/fstab` per il mount persistente al boot.

> **Dettaglio tecnico:** OMV monta i filesystem in `/srv/dev-disk-by-uuid/<UUID>`. Usa l'UUID (Universally Unique Identifier) invece del device name (`/dev/nvme0n1p1`) perche' i device name possono cambiare se aggiungi altri dischi, mentre l'UUID e' legato al filesystem ed e' immutabile.

### 4.3 Cartelle Condivise (Shared Folders)

Vai su **Storage → Shared Folders** e crea le cartelle che vuoi rendere accessibili via rete.

![OMV - Creazione cartelle condivise con permessi](img/omv-shared-folders.jpg)

Per ogni cartella puoi impostare:

- **Nome**: il nome visibile nella rete (es. `Documents`, `Media`, `Backup`)
- **Filesystem**: su quale partizione risiede (la nostra NVMe)
- **Percorso relativo**: la directory sotto il mount point
- **Permessi**: ACL (Access Control List) per utenti e gruppi

**Cosa sono le ACL (Access Control Lists):**

Le ACL estendono il modello di permessi UNIX tradizionale (owner/group/others con rwx). Con le ACL puoi definire permessi specifici per singoli utenti o gruppi, ad esempio:

- Utente `nick`: lettura + scrittura su `Documents`
- Utente `guest`: solo lettura su `Media`
- Gruppo `family`: lettura + scrittura su `Photos`

OMV gestisce le ACL tramite la web UI, ma sotto il cofano usa i comandi `setfacl`/`getfacl` del sistema.

### 4.4 Protocollo SMB/CIFS (per Windows e macOS)

**SMB (Server Message Block)** e' il protocollo nativo di Windows per la condivisione file. La versione moderna (SMB 3.x) supporta crittografia del trasporto, firma digitale dei pacchetti e autenticazione NTLM/Kerberos.

#### Abilitazione del servizio

Vai su **Services → SMB/CIFS → Settings** e abilita il servizio.

![OMV - Abilitazione del servizio SMB/CIFS](img/omv-smb-settings.jpg)

Parametri importanti:

- **Workgroup**: deve corrispondere a quello dei client Windows (default: `WORKGROUP`)
- **Min Protocol/Max Protocol**: SMB2 come minimo - SMB1 e' deprecato e vulnerabile (EternalBlue, WannaCry)

#### Creazione della condivisione

Vai su **Services → SMB/CIFS → Shares** e aggiungi una nuova condivisione collegandola alla Shared Folder creata in precedenza.

![OMV - Configurazione share SMB con permessi](img/omv-smb-shares.jpg)

### 4.5 Protocollo NFS (per Linux e macOS)

**NFS (Network File System)** e' il protocollo nativo di condivisione file nel mondo UNIX/Linux. A differenza di SMB, NFS non ha un concetto nativo di "utente e password" per l'autenticazione - controlla l'accesso in base all'**indirizzo IP o subnet** del client.

| Aspetto | SMB | NFS |
|---|---|---|
| Autenticazione | Username + Password | IP/subnet-based |
| Cifratura | SMB 3.x supporta AES | NFSv4 con Kerberos (raro in home lab) |
| Overhead | Maggiore (negoziazione sessione) | Minore (piu' vicino al filesystem) |
| Caso d'uso | Client Windows/Mac misti | Client Linux/Mac puri |

#### Abilitazione del servizio

Vai su **Services → NFS → Settings** e abilita il servizio.

![OMV - Abilitazione del servizio NFS](img/omv-nfs-settings.jpg)

#### Creazione della condivisione NFS

Vai su **Services → NFS → Shares** e aggiungi una condivisione.

![OMV - Configurazione share NFS con host autorizzati](img/omv-nfs-shares.jpg)

Imposta:

- **Shared Folder**: la cartella creata in precedenza
- **Client**: `192.168.0.0/24` (tutta la rete locale) o un IP specifico
- **Privilege**: `Read/Write` o `Read only`

### 4.6 Test della condivisione di rete

#### Da Windows

Aprire Esplora File e digitare nella barra degli indirizzi:

```
\\192.168.0.102\NomeCondivisione
```

![Accesso alla condivisione NAS da Windows - barra degli indirizzi](img/windows-network-path.jpg)

Windows chiedera' le credenziali:

![Richiesta credenziali per accesso SMB](img/windows-login.jpg)

Inserire username e password dell'utente creato in OMV (NON `admin` - quell'utente e' solo per la web UI).

#### Da Linux

```bash
# Montaggio temporaneo
sudo mount -t cifs //192.168.0.102/NomeCondivisione /mnt/nas -o username=nick

# Montaggio permanente via fstab
echo "//192.168.0.102/NomeCondivisione /mnt/nas cifs credentials=/home/nick/.smbcredentials,uid=1000 0 0" | sudo tee -a /etc/fstab
```

#### Se non funziona

Controllare i permessi utente nella sezione **Access Rights Management → Users**. L'utente deve avere permessi espliciti sulla Shared Folder.

![OMV - Gestione permessi utente sulle cartelle condivise](img/omv-user-permissions.jpg)

Se tutto e' configurato correttamente, vedrai i file condivisi accessibili dai client:

![Condivisione NAS accessibile e funzionante da Windows](img/nas-access-success.jpg)

---

## Step 5: Plex Media Server (Opzionale)

Plex permette di fare streaming dei media presenti sul NAS verso qualsiasi dispositivo (TV, smartphone, tablet).

> **Avvertenza sulle prestazioni:** Plex su Raspberry Pi 5 funziona bene in modalita' **Direct Play** (il client supporta il formato originale del file). Se il client richiede **transcoding** (conversione del formato in tempo reale), la CPU ARM quad-core A76 si saturera' rapidamente, specialmente con video 4K. Consiglio: usare formati compatibili (H.264/AAC in container MP4/MKV) e client che supportano Direct Play.

### Installazione

```bash
# Supporto HTTPS per APT
sudo apt update
sudo apt install apt-transport-https -y

# Chiave GPG di Plex
curl https://downloads.plex.tv/plex-keys/PlexSign.key | sudo gpg --dearmor -o /usr/share/keyrings/plex-archive-keyring.gpg

# Repository Plex
echo "deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] https://downloads.plex.tv/repo/deb public main" | sudo tee /etc/apt/sources.list.d/plexmediaserver.list

# Installazione
sudo apt update
sudo apt install plexmediaserver -y
```

### Verifica e accesso

```bash
sudo systemctl status plexmediaserver
```

Interfaccia web:

```
http://<IP_DEL_RASPBERRY>:32400/web
```

Da qui potrai aggiungere le librerie media puntando alle cartelle condivise del NAS (sotto `/srv/dev-disk-by-uuid/...`).

---

## Consigli di manutenzione

- **Dopo aggiornamenti kernel o firmware**: ricontrollare che l'NVMe sia visibile con `lsblk`
- **Non rimuovere la MicroSD** finche' il boot da NVMe non e' confermato funzionante
- **Monitorare SMART regolarmente**: un NVMe in un case chiuso puo' raggiungere temperature critiche; considerare un dissipatore o il case ufficiale con ventola
- **Backup delle configurazioni OMV**: esportare periodicamente la configurazione da System → Backup

---

## Ha senso un Raspberry Pi come NAS? Quando si' e quando no

Questa e' la prima domanda da farsi. La risposta onesta: **dipende dal carico di lavoro**.

### Quando il Raspberry Pi come NAS ha senso

- **Home lab educativo** (il nostro caso): vuoi imparare Linux, Docker, SIEM, networking. Il Pi costa 80-100 EUR ed e' sufficiente
- **Archivio personale leggero**: foto, documenti, backup periodici. 1-3 utenti simultanei
- **Media server per uso singolo**: Plex/Jellyfin per 1-2 stream simultanei (il Pi5 gestisce transcoding H.264 hardware)
- **Budget limitato**: un NAS Synology 2-bay parte da 300+ EUR senza dischi

### Quando NON ha senso

- **Piu' di 5 utenti simultanei**: il bus USB3/PCIe del Pi satura (~500 MB/s teorici, ~400 MB/s reali)
- **RAID/Ridondanza dati**: il Pi ha un solo slot PCIe — non puoi fare RAID senza hub USB (che aggiunge un collo di bottiglia)
- **Carichi I/O pesanti 24/7**: database, virtual machine, surveillance con 10+ telecamere
- **Affidabilita' enterprise**: il Pi non ha ECC RAM, non ha alimentazione ridondante, un power failure puo' corrompere il filesystem

### Confronto: Raspberry Pi vs NAS dedicati vs Mini-PC

| | RPi 5 (8GB) | Synology DS224+ | QNAP TS-233 | Mini-PC x86 (N100) |
|---|---|---|---|---|
| **Prezzo (solo unita')** | ~80 EUR | ~350 EUR | ~250 EUR | ~150 EUR |
| **CPU** | Cortex-A76 4-core | Celeron J4125 4-core | Cortex-A55 4-core | Intel N100 4-core |
| **RAM** | 8GB LPDDR4X | 2GB DDR4 (exp. 6GB) | 2GB DDR4 | 8-16GB DDR5 |
| **Slot disco** | 1x PCIe + 1x microSD | 2x SATA 3.5" | 2x SATA 3.5" | 1x NVMe + 2x SATA |
| **RAID** | No (singolo disco) | RAID 1 (mirror) | RAID 1 | RAID 1 (con 2 SATA) |
| **Rete** | 1x Gigabit | 1x Gigabit | 1x 2.5GbE | 1-2x 2.5GbE |
| **Consumo** | 5-8W | 15-20W | 10-15W | 15-25W |
| **Docker** | Si (ARM64) | Si (x86) | Si (ARM64) | Si (x86) |
| **Wazuh** | Si (manuale) | Difficile (risorse limitate) | No (2GB RAM) | **Si** (setup standard) |
| **Software NAS** | OMV, CasaOS | Synology DSM (proprietario) | QNAP QTS (proprietario) | OMV, TrueNAS, Unraid |

> **La mia conclusione:** Per il progetto specifico di questo lab (NAS + SIEM + Honeypot + VPN), il Raspberry Pi 5 8GB e' al **limite**. Se dovessi rifare il progetto con budget leggermente superiore, prenderei un mini-PC x86 con N100 (o N200): stessa fascia di prezzo del Pi + alimentatore + case + NVMe, ma con architettura x86 supportata nativamente da tutto (Wazuh, Splunk, Docker immagini standard), piu' RAM espandibile, e 2.5GbE.

### Alternative al Raspberry Pi: altri SBC (Single Board Computer)

| SBC | CPU | RAM | Storage | Prezzo | Pro | Contro |
|---|---|---|---|---|---|---|
| **Orange Pi 5 Plus** | RK3588 (8-core, 4x A76 + 4x A55) | 8-32GB | 2x NVMe M.2 | ~120 EUR | Due slot NVMe (RAID software possibile), 2x 2.5GbE | Software meno maturo, community piu' piccola |
| **ODROID H4 Plus** | Intel N97 (x86, 4-core) | 32GB DDR5 | 2x NVMe + 2x SATA | ~150 EUR | **x86 nativo**, supporto perfetto Docker/Wazuh | Non e' un SBC ARM (piu' simile a un mini-PC) |
| **Rock Pi 5B** | RK3588 | 8-16GB | 1x NVMe + eMMC | ~100 EUR | Buona potenza, NPU per AI | Supporto Linux ancora in maturazione |
| **Banana Pi BPI-R4** | MediaTek MT7988A | 4GB | eMMC + microSD | ~100 EUR | 2x 2.5GbE + Wi-Fi 7, pensato come router | RAM limitata per SIEM |

> **Domanda da farsi:** "Ho bisogno di ARM o di x86?" Se il progetto e' puramente educativo su ARM e vuoi affrontare le sfide di compatibilita', il Pi e' perfetto. Se vuoi che tutto funzioni al primo colpo, un ODROID H4 (x86) elimina il 90% dei problemi documentati in questa repo.

### Alternative a OpenMediaVault: altri software NAS

| Software | Base | Filesystem | Licenza | RPi 5 | Caratteristica unica |
|---|---|---|---|---|---|
| **OpenMediaVault 7** | Debian 12 | EXT4, Btrfs, XFS | GPLv3 | **Si** | Plugin ecosystem, integrazione Debian nativa |
| **TrueNAS Scale** | Debian 12 | **OpenZFS** | BSD | No (solo x86) | ZFS: snapshot, dedup, self-healing, RAIDZ |
| **TrueNAS Core** | FreeBSD | OpenZFS | BSD | No (solo x86) | Stabilita' FreeBSD, bhyve VMs |
| **CasaOS** | Qualsiasi Linux | Qualsiasi | Apache 2.0 | **Si** | UI moderna, app store one-click, leggero |
| **Unraid** | Slackware | XFS + Btrfs (cache) | Proprietario ($59+) | No (solo x86) | Array parity senza RAID tradizionale, Docker/VM |

#### CasaOS: alternativa leggera per chi vuole semplicita'

Se il tuo obiettivo e' solo un NAS con Docker e un'interfaccia bella, CasaOS e' molto piu' leggero di OMV:

```bash
# Installazione CasaOS (una riga)
curl -fsSL https://get.casaos.io | sudo bash

# Dopo l'installazione, accedi su http://<IP>:80
# App store integrato: Pi-hole, Portainer, Jellyfin, Nextcloud in un click
```

| | OMV 7 | CasaOS |
|---|---|---|
| **Complessita' setup** | Media (script + configurazione) | Bassa (un comando) |
| **Gestione disco** | Completa (RAID, SMART, filesystem) | Base (mount e condivisione) |
| **Plugin** | Ampio ecosistema | App store Docker-based |
| **Risorse** | ~200MB RAM | ~80MB RAM |
| **Conflitti con Docker** | Possibili (porta 80, systemd) | Nessuno (Docker-native) |
| **Per il nostro progetto** | **Scelto** (gestione disco avanzata) | Alternativa valida se non serve SMART/RAID |

> **Perche' ho scelto OMV e non CasaOS:** OMV offre gestione disco di livello enterprise (SMART monitoring, scheduler I/O, filesystem tuning, ACL granulari). CasaOS e' piu' user-friendly ma manca di queste funzionalita'. Per un lab di sicurezza dove il disco lavora pesantemente (log SIEM, indici OpenSearch), il controllo offerto da OMV e' necessario.

---

Prossimo step: [Docker & Portainer](../Docker%20%26%20Portainer/) - installare la piattaforma container per tutti i servizi aggiuntivi.
