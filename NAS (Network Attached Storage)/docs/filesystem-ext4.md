# Step 2: Creazione Partizioni e Filesystem

## Partizionamento con GPT

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

## Formattazione EXT4

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

## Deep Dive: EXT4 Journaling Modes

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

## Mount persistente con fstab

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
