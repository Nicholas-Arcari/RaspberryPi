>  [English](risorse-e-credenziali.en.md) |  **Italiano**

# Runbook 09 - Esaurimento risorse e credenziali perse

> **Quando usare questo runbook:** il sistema e' lento o instabile perche' il disco e' pieno, la RAM e' esaurita (OOM) o la CPU va in throttling termico; oppure hai perso la password di uno dei servizi (OMV, Portainer, Pi-hole, WireGuard, Wazuh) e devi resettarla. Due problemi frequenti raggruppati perche' sono le "piccole emergenze" che, ignorate, diventano guasti grossi (un disco pieno tira giu' Docker e Wazuh, vedi [Runbook 03](wazuh-dashboard-recovery.md)).

---

## Parte A - Disco pieno

Un root pieno e' la causa radice piu' sottovalutata: manda in read-only l'indexer di Wazuh, impedisce l'avvio di Docker, blocca i log e simula mille guasti diversi.

### A.1 Diagnosi: quanto e chi

```bash
# Quanto spazio resta sul root?
df -h /
# Uso > 90% <-- zona di pericolo. > 95% <-- OpenSearch va read-only

# Chi occupa lo spazio? I soliti sospetti su questo lab:
sudo du -xh --max-depth=2 /var 2>/dev/null | sort -rh | head -15
# Candidati tipici:
#   /var/log/journal      -> log systemd senza tetto
#   /var/lib/docker       -> immagini e log container
#   /var/ossec/logs       -> log/alert Wazuh
#   /var/lib/wazuh-indexer -> indici OpenSearch che crescono all'infinito
```

### A.2 Bonifica, dal piu' sicuro al piu' aggressivo

```bash
# 1. Log systemd: metti un tetto (sicuro)
sudo journalctl --vacuum-size=200M
# permanente: in /etc/systemd/journald.conf -> SystemMaxUse=200M

# 2. Log e immagini Docker inutilizzate (attenzione: -a rimuove le immagini non in uso)
docker system df                       # mostra dove sta lo spazio Docker
docker image prune -a                  # rimuove immagini dangling/non usate
docker builder prune                   # cache di build
# limita i log container in futuro: in /etc/docker/daemon.json ->
#   "log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}

# 3. Log applicativi vecchi (Cowrie puo' generare molto sotto attacco)
sudo find /var/log -type f -name "*.gz" -mtime +14 -delete
docker exec cowrie sh -c 'find /home/cowrie/cowrie-git/var/log -name "*.json" -mtime +14'

# 4. Indici Wazuh vecchi: la cura strutturale e' una ISM policy di retention.
#    Elimina indici obsoleti (adatta il pattern e la data):
curl -sk -u admin:admin "https://localhost:9200/_cat/indices/wazuh-alerts-*?v&s=index"
curl -sk -u admin:admin -X DELETE "https://localhost:9200/wazuh-alerts-4.x-2025.01.*"
```

### A.3 Sbloccare cio' che si e' bloccato per il disco pieno

```bash
# OpenSearch resta read-only anche dopo aver liberato spazio: va sbloccato
curl -sk -u admin:admin -X PUT "https://localhost:9200/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'

# Docker non partito per disco pieno: dopo la bonifica
sudo systemctl start docker
```

---

## Parte B - RAM esaurita (OOM)

Sul Pi 5 (8GB), Wazuh Indexer + Dashboard + i container competono per la memoria. Quando finisce, il kernel invoca l'**OOM killer** che uccide un processo a sua scelta (spesso proprio l'indexer Java, il piu' grosso).

```bash
# Chi e' stato ucciso dall'OOM killer?
sudo dmesg -T | grep -i "killed process"
# "Out of memory: Killed process 1234 (java)" -> era l'indexer

# Stato attuale di RAM e swap
free -h
# swap a 0 e RAM quasi piena <-- nessun cuscinetto: il prossimo picco uccide qualcosa
```

Rimedi:

```bash
# 1. Limita la heap dell'indexer (il divoratore n.1). In /etc/wazuh-indexer/jvm.options:
#    -Xms1g / -Xmx1g  (non piu' di 1-2g su un Pi condiviso)
sudo systemctl restart wazuh-indexer

# 2. Metti un tetto RAM ai container non critici (cosi' non uccidono l'indexer)
#    nel compose:  mem_limit: 256m   (es. cowrie, pihole)

# 3. Aggiungi swap come cuscinetto (non come soluzione strutturale)
sudo dphys-swapfile swapoff
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo dphys-swapfile setup && sudo dphys-swapfile swapon
```

---

## Parte C - Throttling termico

Il Pi 5 sotto carico (o con dissipazione scarsa) supera gli ~80-85 C e riduce la frequenza per proteggersi: il sistema diventa lentissimo senza motivo apparente.

```bash
# Temperatura e stato di throttling
vcgencmd measure_temp
vcgencmd get_throttled
# 0x0 = tutto ok
# bit 0x1 = under-voltage ORA; 0x4 = throttling ORA; 0x8 = limite freq attivo
# 0x50000/0x50005 = e' gia' successo (under-voltage/throttling nel passato)
```

| Valore | Significato | Rimedio |
|---|---|---|
| Temp > 80 C | Dissipazione insufficiente | Dissipatore attivo/ventola, migliore ventilazione, case aperto |
| `throttled` con bit under-voltage | Alimentatore inadeguato | Alimentatore ufficiale 27W (l'NVMe aumenta il consumo) |

> Under-voltage e throttling termico sono spesso scambiati per problemi software (panic casuali, lentezza, reboot). Su questo lab, con NVMe collegato, l'alimentatore giusto e una dissipazione adeguata prevengono un'intera classe di guasti apparentemente misteriosi. Vedi anche [Runbook 01, Parte C](accesso-perso-e-boot.md).

---

## Parte D - Credenziali perse: reset per servizio

Hai perso l'accesso a un servizio. Ecco il reset per ciascuno. (SSH e' nel [Runbook 01](accesso-perso-e-boot.md); Wazuh nel [Runbook 03](wazuh-dashboard-recovery.md).)

### OpenMediaVault (admin web UI)

```bash
# Da shell (SSH/console), reset password dell'admin OMV
sudo omv-firstaid
# Menu interattivo -> "Change the web control panel password"
# In alternativa, reset diretto:
sudo omv-confdbadm read conf.webadmin       # verifica utente
```

### Portainer (admin web UI)

Portainer permette il reset solo con accesso alla shell dell'host, tramite un container ufficiale che rigenera l'admin:

```bash
docker stop portainer
docker run --rm -v portainer_data:/data portainer/helper-reset-password
# Stampa una nuova password temporanea per l'utente admin
docker start portainer
```

### Pi-hole (dashboard)

```bash
# Imposta una nuova password della dashboard
docker exec -it pihole pihole -a -p
# Digita la nuova password (o lascia vuoto per rimuoverla, sconsigliato)
```

### WireGuard (wg-easy web UI)

La password della UI di wg-easy e' un hash nella variabile d'ambiente del compose. Reset:

```bash
# Genera il nuovo hash (bcrypt) e sostituiscilo in PASSWORD_HASH nel compose/.env
docker run --rm ghcr.io/wg-easy/wg-easy wgpw 'NuovaPassword'
# Copia l'hash risultante in docker-compose.yml (o .env), poi:
docker compose up -d --force-recreate wireguard
```

> **La lezione:** ognuno di questi reset richiede accesso alla shell dell'host. E' un promemoria che **l'accesso all'host e' la chiave madre**: proteggilo (Runbook 01) e mettine le credenziali di recovery nel password manager offline. E dopo ogni reset, **aggiorna il password manager**: il prossimo "ho perso la password" deve essere l'ultimo.

---

## Prevenzione

- **Disco:** tetto ai log (journald + Docker), ISM policy di retention su Wazuh, e un alert Wazuh quando `/` supera l'80%. Il disco pieno e' prevenibile al 100%.
- **RAM:** heap dell'indexer limitata, `mem_limit` sui container, swap come cuscinetto. Fai monitorare la RAM.
- **Termico:** dissipazione adeguata + alimentatore ufficiale. Controlla `get_throttled` nella checklist periodica.
- **Credenziali:** tutte nel password manager, incluse quelle di recovery. Una credenziale che vive solo nella tua testa e' un incidente in attesa.

---

## Collegamenti

- Disco pieno che ha causato il crash di Wazuh -> [Runbook 03: Wazuh dashboard](wazuh-dashboard-recovery.md)
- Container ucciso per OOM (exit 137) -> [Runbook 04: VPN e container](vpn-e-container-recovery.md)
- Under-voltage / panic termici -> [Runbook 01: accesso perso e boot](accesso-perso-e-boot.md)
- Salvare le credenziali nel backup -> [Runbook 08: backup e disaster recovery](backup-e-disaster-recovery.md)
