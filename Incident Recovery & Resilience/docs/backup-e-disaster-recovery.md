>  [English](backup-e-disaster-recovery.en.md) |  **Italiano**

# Runbook 08 - Backup e disaster recovery

> **Quando usare questo runbook:** per progettare cosa salvare e come (prima del disastro), e per ricostruire l'intero lab da zero se il Pi muore, l'NVMe si corrompe o una compromissione impone una reinstallazione pulita (dopo il [Runbook 06](integrita-post-downtime.md)). E' la rete di sicurezza su cui poggiano tutti gli altri runbook.

Tre principi guidano ogni decisione:

1. **Separare i binari dai dati.** I binari (OS, pacchetti, immagini Docker) si **ricreano** da script e registry: non serve fare il backup del sistema, serve poterlo ricostruire. I **dati e le configurazioni** sono l'unica cosa irreproducibile: sono cio' che va salvato.
2. **La regola 3-2-1.** Almeno **3** copie dei dati, su **2** supporti diversi, di cui **1** off-site (fuori casa/fuori dal Pi). Un backup sullo stesso NVMe che stai proteggendo non e' un backup.
3. **Un backup non testato non e' un backup** (Regola d'oro n.3): la procedura di restore va provata almeno una volta a freddo.

---

## Parte A - Cosa salvare (analisi per RPO)

Non tutto ha lo stesso valore. Per ogni componente, l'RPO (quanti dati posso perdere) decide cosa entra nel backup.

| Componente | Cosa salvare | RPO | Perche' |
|---|---|---|---|
| **OMV** | Config di sistema (`omv-confdbadm read ...` / backup nativo OMV), `/etc/openmediavault/config.xml` | Basso | Ricreare condivisioni, utenti, permessi a mano e' lungo |
| **Docker** | I file `docker-compose.yml` + gli `.env` + i **volumi** montati | Basso | I volumi contengono i dati dei servizi (config Pi-hole, DB, ecc.) |
| **Wazuh** | `/var/ossec/etc/` (ossec.conf, regole/decoder custom), `/etc/wazuh-*`, i certificati, le password | Vicino a zero | Le regole custom (Cowrie 100010-100013) sono lavoro puro |
| **WireGuard** | Le **chiavi private** del server e le config dei peer (volume wg-easy) | Vicino a zero | Perdere le chiavi = riconfigurare ogni client |
| **Pi-hole** | Export "Teleporter" (blocklist, whitelist, config), o il volume | Medio | Le liste si riscaricano, ma le personalizzazioni no |
| **Sicurezza host** | `/etc/ufw/`, `/etc/fail2ban/jail.local`, `/etc/ssh/sshd_config`, `/etc/sysctl.d/` | Basso | Ricostruire l'hardening a memoria e' rischioso |
| **Identita' host** | Chiavi host SSH (`/etc/ssh/ssh_host_*`), `authorized_keys` | Medio | Evita il warning "host key changed" ai client dopo il restore |
| **Automazione** | `scripts/setup.sh` (gia' in git) | - | E' la ricetta per ricreare i binari |
| **Baseline** | Hash binari, MAC gateway, fingerprint SSH, elenco porte/utenti | Basso | Serve ai Runbook 05 e 06; va salvata da sani |

Nota: **NON** serve fare il backup di `/var/lib/docker` (le immagini) ne' del sistema operativo: si ricreano con `docker compose pull` e `setup.sh`.

---

## Parte B - Come salvare

### B.1 Configurazioni e file critici (uno script ripetibile)

```bash
#!/usr/bin/env bash
# backup-config.sh - salva le sole configurazioni irreproducibili
set -euo pipefail
DEST="/mnt/backup/rpi-$(date +%F)"     # su un disco/condivisione SEPARATO dal Pi
mkdir -p "$DEST"

# Sicurezza host e identita'
sudo tar czf "$DEST/host-security.tgz" \
  /etc/ufw /etc/fail2ban /etc/ssh/sshd_config /etc/sysctl.d \
  /etc/ssh/ssh_host_* /root/.ssh/authorized_keys 2>/dev/null || true

# Wazuh (config, regole, certificati)
sudo tar czf "$DEST/wazuh.tgz" /var/ossec/etc /etc/wazuh-indexer /etc/wazuh-dashboard 2>/dev/null || true

# OMV config
sudo cp /etc/openmediavault/config.xml "$DEST/omv-config.xml" 2>/dev/null || true

# Compose + env di tutti i servizi (adatta il percorso)
sudo tar czf "$DEST/docker-compose.tgz" /path/al/compose 2>/dev/null || true

echo "Backup in $DEST"
ls -lh "$DEST"
```

### B.2 Volumi Docker (i dati dei servizi)

```bash
# Backup di un volume named senza fermare per forza il servizio (meglio a container fermo)
docker run --rm -v <nome_volume>:/data -v /mnt/backup:/backup alpine \
  tar czf /backup/<nome_volume>-$(date +%F).tgz -C /data .
# Ripeti per i volumi di pihole, wireguard, portainer, cowrie
```

### B.3 Export nativi dei servizi

```bash
# Pi-hole: Teleporter (dalla dashboard: Settings -> Teleporter -> Backup) o CLI
docker exec pihole pihole -a -t                 # crea un archivio teleporter

# OMV: backup nativo della config dalla web UI (System -> ... -> Config Backup)
```

### B.4 Dove mettere i backup (3-2-1)

- **Copia 1:** sul NAS stesso ma su un **disco diverso** dall'NVMe di boot (se presente).
- **Copia 2:** su un disco USB esterno / un altro PC in LAN (via la condivisione SMB del NAS).
- **Copia 3 (off-site):** cloud cifrato o un disco che tieni fuori casa. Cifra sempre i backup che escono di casa (contengono chiavi e password): `gpg -c` o `age`.

---

## Parte C - Disaster recovery: ricostruire da zero

Scenario: l'NVMe e' morto o il sistema e' compromesso. Ricostruzione pulita in ordine.

```
[1] Reinstallare la base           [4] Ripristinare i DATI (non i binari)
    - flash OS su nuovo NVMe/SD         - config OMV, volumi Docker
    - boot, rete, SSH                   - config+regole Wazuh, chiavi WireGuard
        |                                   |
        v                                   v
[2] Ricreare i binari              [5] Ripristinare identita' e sicurezza
    - scripts/setup.sh all             - chiavi host SSH, authorized_keys
    - docker compose pull/up           - ufw, fail2ban, sysctl
        |                                   |
        v                                   v
[3] Rimettere i servizi            [6] Verificare
    - Wazuh (installazione manuale)    - checklist post-installazione
    - container dai compose            - Runbook 05 (difese) + Runbook 00 (triage)
```

Passi concreti:

```bash
# [1] Flash Raspberry Pi OS Lite 64-bit sul nuovo NVMe (o boot da SD di recovery),
#     configura rete e SSH. Vedi First Setup.

# [2] Clona il repo e lancia l'automazione (ricrea hardening, Docker, ecc.)
git clone <questo-repo> && cd RaspberryPi
sudo ./scripts/setup.sh all       # o i singoli moduli: hardening, docker, pihole...

# [3][4] Ripristina i dati sopra ai servizi ricreati
sudo tar xzf /mnt/backup/rpi-<data>/host-security.tgz -C /
sudo tar xzf /mnt/backup/rpi-<data>/wazuh.tgz -C /
# volumi Docker:
docker run --rm -v <vol>:/data -v /mnt/backup:/backup alpine \
  sh -c "cd /data && tar xzf /backup/<vol>-<data>.tgz"

# [5] Sistema proprietari/permessi dei certificati Wazuh (vedi Runbook 03)
sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs
sudo systemctl restart wazuh-indexer wazuh-manager wazuh-dashboard filebeat

# [6] Verifica
# esegui la checklist post-installazione e il Runbook 05
```

> **Wazuh a mano:** come nota il README del progetto, l'installazione Wazuh su ARM64 non e' automatizzata (ogni passo richiede verifica). In DR, reinstalli Wazuh seguendo la sua guida e poi ripristini **solo** config, regole e certificati dal backup. Vedi [SOC Analyst / Wazuh / installazione](../../SOC%20Analyst/Wazuh/docs/installazione.md).

---

## Parte D - Il DR drill (provare il restore)

Un backup diventa affidabile solo dopo un test. Esegui il drill almeno una volta e dopo ogni cambiamento importante:

1. Prendi un **secondo NVMe o una MicroSD** (non toccare il sistema di produzione).
2. Esegui la Parte C completa **dai soli backup**, senza guardare il sistema vivo.
3. Cronometra: e' il tuo **RTO reale** di ricostruzione totale. Annotalo.
4. Segna **cosa mancava** (una config non nel backup, un passo non documentato): e' esattamente il valore del drill. Aggiorna `backup-config.sh` di conseguenza.
5. Verifica il risultato con il [Runbook 05](verifica-difese-attive.md).

> Un drill che scopre "mi ero dimenticato le chiavi WireGuard nel backup" ti ha appena salvato da un disastro reale. E' scienza applicata al proprio lab: si testa l'ipotesi ("posso ripristinare") invece di assumerla.

---

## Prevenzione / cadenza

- **Automatizza** `backup-config.sh` con un cron settimanale + export volumi a container fermi (finestra notturna).
- **Verifica l'integrita'** dei backup periodicamente (`tar tzf` per elencare senza estrarre; un archivio corrotto e' inutile).
- **Cifra** i backup off-site: contengono chiavi e password.
- **Ripeti il DR drill** almeno una volta l'anno e dopo ogni cambio architetturale.
- Tieni **il repo (con `setup.sh`) e i backup dei dati separati**: il primo e' pubblico e ricrea i binari, i secondi sono privati e cifrati.

---

## Collegamenti

- Reinstallazione pulita dopo compromissione -> [Runbook 06: integrita' post-downtime](integrita-post-downtime.md)
- Recupero NVMe / boot da SD -> [Runbook 01: accesso perso e boot](accesso-perso-e-boot.md)
- Ripristino singoli container/volumi -> [Runbook 04: VPN e container](vpn-e-container-recovery.md)
- Verifica post-restore -> [Runbook 05: verifica difese attive](verifica-difese-attive.md)
- Setup iniziale di riferimento -> [First Setup](../../First%20Setup/)
