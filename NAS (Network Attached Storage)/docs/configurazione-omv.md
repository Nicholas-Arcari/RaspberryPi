# Step 4: Configurazione OMV - Passo per Passo

## 4.1 Gestione Dischi

Vai su **Storage → Disks**. Qui vedrai tutti i dispositivi di storage rilevati dal kernel.

![OMV - Vista dei dischi collegati: MicroSD da 58GB e NVMe Patriot P320 da 238GB](../img/omv-disks.jpg)

Nell'immagine si vede:
- `/dev/mmcblk0` - la MicroSD da 58.30 GiB (boot)
- `/dev/nvme0n1` - l'NVMe Patriot M.2 P320 256GB (storage NAS)

Da questa vista puoi anche controllare lo stato **SMART** del disco cliccando sull'icona dell'ingranaggio. SMART (Self-Monitoring, Analysis and Reporting Technology) e' un sistema di diagnostica integrato in ogni SSD/HDD che monitora parametri come:

- **Temperature**: un NVMe in un case chiuso puo' surriscaldarsi - sopra i 70C le prestazioni calano (thermal throttling)
- **Percentage Used**: indica quanta vita residua ha l'SSD basandosi sui cicli di scrittura consumati
- **Media Errors**: errori non correggibili nella NAND - se questo numero cresce, il disco sta morendo

## 4.2 Gestione Filesystem

Vai su **Storage → File Systems**. Se hai formattato il disco da CLI (Step 2), vedrai la partizione EXT4 gia' presente. Altrimenti, puoi crearla da qui.

![OMV - Gestione filesystem: partizioni montate e disponibili](../img/omv-filesystems.jpg)

Seleziona la partizione NVMe e clicca **Mount**. OMV aggiungera' automaticamente l'entry in `/etc/fstab` per il mount persistente al boot.

> **Dettaglio tecnico:** OMV monta i filesystem in `/srv/dev-disk-by-uuid/<UUID>`. Usa l'UUID (Universally Unique Identifier) invece del device name (`/dev/nvme0n1p1`) perche' i device name possono cambiare se aggiungi altri dischi, mentre l'UUID e' legato al filesystem ed e' immutabile.

## 4.3 Cartelle Condivise (Shared Folders)

Vai su **Storage → Shared Folders** e crea le cartelle che vuoi rendere accessibili via rete.

![OMV - Creazione cartelle condivise con permessi](../img/omv-shared-folders.jpg)

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

## 4.4 Protocollo SMB/CIFS (per Windows e macOS)

**SMB (Server Message Block)** e' il protocollo nativo di Windows per la condivisione file. La versione moderna (SMB 3.x) supporta crittografia del trasporto, firma digitale dei pacchetti e autenticazione NTLM/Kerberos.

### Abilitazione del servizio

Vai su **Services → SMB/CIFS → Settings** e abilita il servizio.

![OMV - Abilitazione del servizio SMB/CIFS](../img/omv-smb-settings.jpg)

Parametri importanti:

- **Workgroup**: deve corrispondere a quello dei client Windows (default: `WORKGROUP`)
- **Min Protocol/Max Protocol**: SMB2 come minimo - SMB1 e' deprecato e vulnerabile (EternalBlue, WannaCry)

### Creazione della condivisione

Vai su **Services → SMB/CIFS → Shares** e aggiungi una nuova condivisione collegandola alla Shared Folder creata in precedenza.

![OMV - Configurazione share SMB con permessi](../img/omv-smb-shares.jpg)

## 4.5 Protocollo NFS (per Linux e macOS)

**NFS (Network File System)** e' il protocollo nativo di condivisione file nel mondo UNIX/Linux. A differenza di SMB, NFS non ha un concetto nativo di "utente e password" per l'autenticazione - controlla l'accesso in base all'**indirizzo IP o subnet** del client.

| Aspetto | SMB | NFS |
|---|---|---|
| Autenticazione | Username + Password | IP/subnet-based |
| Cifratura | SMB 3.x supporta AES | NFSv4 con Kerberos (raro in home lab) |
| Overhead | Maggiore (negoziazione sessione) | Minore (piu' vicino al filesystem) |
| Caso d'uso | Client Windows/Mac misti | Client Linux/Mac puri |

### Abilitazione del servizio

Vai su **Services → NFS → Settings** e abilita il servizio.

![OMV - Abilitazione del servizio NFS](../img/omv-nfs-settings.jpg)

### Creazione della condivisione NFS

Vai su **Services → NFS → Shares** e aggiungi una condivisione.

![OMV - Configurazione share NFS con host autorizzati](../img/omv-nfs-shares.jpg)

Imposta:

- **Shared Folder**: la cartella creata in precedenza
- **Client**: `192.168.0.0/24` (tutta la rete locale) o un IP specifico
- **Privilege**: `Read/Write` o `Read only`

## 4.6 Test della condivisione di rete

### Da Windows

Aprire Esplora File e digitare nella barra degli indirizzi:

```
\\192.168.0.102\NomeCondivisione
```

![Accesso alla condivisione NAS da Windows - barra degli indirizzi](../img/windows-network-path.jpg)

Windows chiedera' le credenziali:

![Richiesta credenziali per accesso SMB](../img/windows-login.jpg)

Inserire username e password dell'utente creato in OMV (NON `admin` - quell'utente e' solo per la web UI).

### Da Linux

```bash
# Montaggio temporaneo
sudo mount -t cifs //192.168.0.102/NomeCondivisione /mnt/nas -o username=nick

# Montaggio permanente via fstab
echo "//192.168.0.102/NomeCondivisione /mnt/nas cifs credentials=/home/nick/.smbcredentials,uid=1000 0 0" | sudo tee -a /etc/fstab
```

### Se non funziona

Controllare i permessi utente nella sezione **Access Rights Management → Users**. L'utente deve avere permessi espliciti sulla Shared Folder.

![OMV - Gestione permessi utente sulle cartelle condivise](../img/omv-user-permissions.jpg)

Se tutto e' configurato correttamente, vedrai i file condivisi accessibili dai client:

![Condivisione NAS accessibile e funzionante da Windows](../img/nas-access-success.jpg)
