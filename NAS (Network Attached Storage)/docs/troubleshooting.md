>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting - NAS / OpenMediaVault: problemi reali e soluzioni

> Problemi tipici di OpenMediaVault 7 su Raspberry Pi: disco non rilevato dalla UI, web UI irraggiungibile, condivisioni SMB/NFS che non si montano, il modello di permessi a strati, e la trappola classica della rigenerazione delle config. Per l'esaurimento dello spazio disco lato operativo vedi [Incident Recovery / risorse e credenziali](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.md).

---

## Problema 1: OMV sovrascrive le mie modifiche ai file di config

**Sintomo:** modifichi a mano un file in `/etc` (es. `sshd_config`, `smb.conf`, `exports`) e dopo un cambiamento dalla web UI - o un reboot - la modifica sparisce.

**Causa:** e' il comportamento fondamentale di OMV, non un bug. OMV tiene la **verita' in un database** (`/etc/openmediavault/config.xml`) e **rigenera** i file di `/etc` da template tramite `omv-salt`. Qualsiasi modifica manuale ai file generati viene sovrascritta alla prima rigenerazione.

**Soluzione:** configura **dalla web UI di OMV** dove possibile (le impostazioni finiscono nel database e sopravvivono). Se devi personalizzare oltre quello che la UI espone, usa i campi "Extra options" presenti in molte sezioni OMV, oppure gli override documentati. Per applicare/rigenerare manualmente:

```bash
# Rigenera un servizio specifico dalle impostazioni del database
sudo omv-salt deploy run <servizio>     # es. samba, ssh, nfs
# Leggi cosa c'e' nel database (la vera fonte di verita')
sudo omv-confdbadm read conf.service.smb
```

---

## Problema 2: L'NVMe (o un disco) non appare nella UI di OMV

**Sintomo:** il disco esiste (`lsblk` lo mostra) ma OMV non lo elenca in Storage -> Disks, o non lo lascia formattare.

**Causa:** quasi sempre il disco ha **signature di partizioni/filesystem precedenti** che confondono OMV, oppure e' gia' montato/in uso.

**Soluzione:**

```bash
# Verifica cosa vede il kernel
lsblk -f /dev/nvme0n1

# Mostra e poi rimuovi le signature residue (ATTENZIONE: distruttivo per i dati sul disco)
sudo wipefs /dev/nvme0n1
sudo wipefs -a /dev/nvme0n1     # rimuove partition table e magic bytes dei filesystem
```

> **CRITICO:** non eseguire mai `wipefs` sul disco da cui fai boot. Controlla sempre con `lsblk` quale sia `mmcblk0`/`nvme0n1` di sistema prima di procedere. Se l'NVMe non appare proprio nemmeno in `lsblk`, il problema e' a monte: vedi [First Setup / troubleshooting, Problema 1](../../First%20Setup/docs/troubleshooting.md).

---

## Problema 3: La web UI di OMV non e' raggiungibile (porta 80)

**Sintomo:** `http://192.168.0.102` non apre, timeout o "connection refused".

**Causa:** il servizio web di OMV (nginx, `openmediavault-webgui`) e' fermo, oppure un altro servizio ha occupato la porta 80.

**Soluzione:**

```bash
# Il frontend web di OMV e' su?
sudo systemctl status openmediavault-engined nginx
sudo systemctl restart openmediavault-engined nginx

# Chi occupa la porta 80?
sudo ss -tulnp | grep :80
# Nel lab, Pi-hole gira su un IP MacVLAN dedicato (192.168.0.250), quindi NON confligge
# con la 80 dell'host. Se vedi un conflitto, e' un altro servizio da spostare.

# Reset di emergenza della configurazione web (utente/password admin)
sudo omv-firstaid     # menu interattivo -> ripristina accesso web UI
```

---

## Problema 4: La condivisione SMB non si apre da Windows

**Sintomo:** da Windows, `\\192.168.0.102\condivisione` da' errore di credenziali o "non raggiungibile", anche se le credenziali sono giuste.

**Causa:** tipicamente una di queste: Windows ha **cachato vecchie credenziali**, il servizio SMB non e' attivo, l'utente non ha i **privilegi** sulla cartella condivisa, o il client tenta SMB1 (disabilitato per sicurezza).

**Soluzione:**

```bash
# Sul Pi: il servizio Samba e' attivo e la condivisione esiste?
sudo systemctl status smbd
sudo smbclient -L localhost -U <utente>     # elenca le condivisioni viste dal server

# Su Windows: pulisci le credenziali cachate (causa n.1 dei falsi "accesso negato")
#   net use * /delete
#   Gestione credenziali -> rimuovi le voci per 192.168.0.102
```

Checklist lato OMV:
- L'utente esiste in OMV (Users) e ha una password SMB impostata.
- La cartella condivisa ha i **privilegi** corretti per quell'utente (Shared Folders -> Privileges: Read/Write).
- In Services -> SMB/CIFS la condivisione e' abilitata.
- Se un client vecchio richiede SMB1: **non riabilitarlo**; aggiorna il client. SMB1 e' insicuro (EternalBlue).

---

## Problema 5: Il mount NFS fallisce da Linux

**Sintomo:** `mount -t nfs 192.168.0.102:/export /mnt` da' "access denied" o "permission denied".

**Causa:** il client non e' tra gli IP autorizzati nell'export, oppure c'e' un problema di squashing dei permessi (UID/GID).

**Soluzione:**

```bash
# Sul Pi: quali export sono pubblicati e verso chi?
sudo exportfs -v
showmount -e 192.168.0.102

# Sul client: l'IP deve rientrare nel range autorizzato nell'export OMV
sudo mount -t nfs 192.168.0.102:/export/condivisione /mnt -o vers=4
```

Checklist lato OMV (Services -> NFS):
- L'export esiste ed elenca il **client/subnet** giusto (es. `192.168.0.0/24`), non un singolo IP sbagliato.
- I permessi della cartella condivisa consentono l'accesso all'UID che monta.
- Preferisci `root_squash` (default sicuro): mappa il root del client a `nobody`. Evita `no_root_squash` se non strettamente necessario (e' un vettore di privilege escalation).

---

## Problema 6: Confusione sui permessi (il modello a tre strati di OMV)

**Sintomo:** un utente puo' vedere ma non scrivere (o viceversa) in modo incoerente tra SMB, NFS e SSH.

**Causa:** OMV applica i permessi su **tre livelli** che si sommano, e il piu' restrittivo vince: (1) permessi POSIX/ACL del filesystem, (2) permessi della **cartella condivisa** (Shared Folder), (3) **privilegi per-servizio** (le ACL specifiche di SMB/NFS). Un utente con Read/Write a livello SMB ma con la cartella condivisa in read-only resta in sola lettura.

**Soluzione:** verifica in ordine, dal filesystem al servizio.

```bash
# Livello 1: permessi POSIX/ACL reali sulla directory
getfacl /srv/dev-disk-by-*/condivisione

# Livello 2 e 3 si controllano dalla web UI:
#   Storage -> Shared Folders -> (cartella) -> Permissions / ACL
#   Services -> SMB or NFS -> (share) -> Privileges
```

Regola pratica: definisci i permessi in **un solo posto** (i privilegi della Shared Folder) e lascia gli altri livelli permissivi ma coerenti, per non impazzire a debuggare intersezioni.

---

## Problema 7: Plex non e' raggiungibile o va a scatti

**Sintomo:** Plex non appare in rete, chiede un "claim", o la riproduzione va a scatti.

**Causa:** manca il claim token iniziale, oppure il Pi sta **transcodificando** (operazione pesantissima per la CPU ARM).

**Soluzione:**
- Al primo avvio, associa il server con il claim token da `https://plex.tv/claim` (scade in 4 minuti: generane uno fresco).
- Forza il **Direct Play/Direct Stream** ed evita il transcoding: il Pi 5 non ha una GPU adatta al transcoding hardware di flussi multipli. Prepara i media in formati gia' compatibili con i client.
- Verifica risorse durante la riproduzione: `docker stats plex` (se in container) o `top`.

---

## Problema 8: Un aggiornamento rischia di rompere OMV

**Sintomo:** dopo un aggiornamento aggressivo, servizi OMV non ripartono o la UI da' errori.

**Causa:** OMV gestisce e "pinna" alcuni pacchetti; un upgrade di versione maggiore fatto a mano puo' disallineare i componenti.

**Soluzione:** aggiorna dalla **web UI di OMV** (System -> Update Management) o con gli strumenti OMV, non con upgrade di release Debian arbitrari. Per gli aggiornamenti di sistema ordinari:

```bash
sudo apt update && sudo apt upgrade -y     # aggiornamenti di sicurezza ordinari
# Per major release OMV usa la procedura ufficiale omv-release-upgrade, non a mano
```

Prima di qualsiasi aggiornamento importante, fai il backup della config (System -> ... -> Config Backup) e includilo nel [Runbook 08 di backup](../../Incident%20Recovery%20%26%20Resilience/docs/backup-e-disaster-recovery.md).

---

## Comandi utili di verifica

```bash
# Stato dei servizi NAS core
sudo systemctl status openmediavault-engined smbd nfs-kernel-server

# Salute dei dischi (SMART)
sudo smartctl -H /dev/nvme0n1
sudo smartctl -a /dev/nvme0n1 | grep -Ei "temperature|percentage used|media errors"

# Cosa e' montato e con quali opzioni
findmnt -t ext4,nfs4,cifs

# Leggi la vera config di un servizio dal database OMV
sudo omv-confdbadm read conf.service.smb
```

---

## Collegamenti

- Disco pieno / risorse esaurite (lato operativo) -> [Incident Recovery / risorse e credenziali](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.md)
- Preparazione e pulizia del disco -> [preparazione-nvme](preparazione-nvme.md)
- Condivisioni SMB/NFS in dettaglio -> [configurazione-omv](configurazione-omv.md)
- Backup della configurazione OMV -> [Incident Recovery / backup e disaster recovery](../../Incident%20Recovery%20%26%20Resilience/docs/backup-e-disaster-recovery.md)
