# Wazuh (SIEM & XDR)

Wazuh è una piattaforma open-source per sicurezza e monitoraggio dei sistemi. Fornisce funzionalità come:

- Intrusion Detection (IDS) - rileva attività sospette sui file di sistema e sulla rete.
- File Integrity Monitoring (FIM) - controlla modifiche non autorizzate ai file critici.
- Gestione delle vulnerabilità - monitora pacchetti e configurazioni per rischi di sicurezza.
- Centralizzazione dei log e analisi - raccoglie e analizza i log dei sistemi gestiti.

Su un Raspberry Pi, Wazuh può essere installato solo come Manager leggero, perché:

- Componenti come Indexer (OpenSearch) e Dashboard richiedono molta RAM e CPU e non sono compatibili con l’architettura ARM64.
- Il Raspberry Pi può monitorare i propri file, processi e log, ma non può eseguire la UI web o il motore di ricerca completo senza un server x86_64 esterno.

In pratica, Wazuh su Raspberry Pi diventa un agente locale potente per sicurezza e monitoraggio, ma non può sostituire un ambiente completo di produzione con Dashboard e Indexer.

Wazuh è progettato principalmente per architetture x86_64 e richiede servizi pesanti come l’Indexer (OpenSearch) e il Dashboard, che fanno un uso intensivo di memoria e CPU. Su Raspberry Pi (aarch64/ARM), la versione ufficiale dei container Docker per Wazuh non è compatibile:

- I container sono costruiti per amd64, non per ARM64, causando errori di “exec format” all’avvio.
- Anche forzando platform: linux/amd64, la limitata memoria e le differenze architetturali impediscono a OpenSearch e al Dashboard di partire correttamente.
- Funzionano solo i componenti leggeri del Manager, ma senza Dashboard e Indexer la UI web non è disponibile.

Soluzione consigliata: installare Wazuh Manager direttamente su Raspberry Pi per la parte di monitoraggio, oppure usare un sistema x86_64 per Indexer e Dashboard, collegato al Manager remoto.

---

## Componenti Wazuh

| Componente                 | Ruolo                                    | Risorse richieste                    |
| -------------------------- | ---------------------------------------- | ------------------------------------ |
| Wazuh Manager              | Raccoglie e analizza eventi di sicurezza | Leggero, adatto a RPi                |
| Wazuh Indexer (OpenSearch) | Indicizza eventi per ricerca e dashboard | Molto pesante, >1 GB RAM consigliata |
| Wazuh Dashboard            | Interfaccia web per visualizzare eventi  | Moderato, dipende dall’Indexer       |


---

## Installare Wazuh Manager

Verifica architettura:

```bash
uname -m
```

Deve uscire: `aarch64`

Aggiorna il sistema:

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

Dopo il reboot rientra via SSH

### Aggiungi repository ufficiale Wazuh (ARM64)

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt update
```

Installa Wazuh Manager

```bash
sudo apt install wazuh-manager -y
```

Se ci mette un po’, è normale

### Avvia e abilita Wazuh:

```bash
sudo systemctl enable wazuh-manager
sudo systemctl start wazuh-manager
```

Verifica:

```bash
sudo systemctl status wazuh-manager
```

Devi vedere:

```bash
Active: active (running)
```

Verifica che Wazuh stia funzionando:

```bash
sudo /var/ossec/bin/wazuh-control status
```

Output atteso (simile):

```bash
wazuh-manager is running
```

Controlla i log

```bash
sudo tail -n 50 /var/ossec/logs/ossec.log
```

Se non vedi errori fatali, sei operativo

### Verificare che Wazuh stia davvero lavorando

```bash
sudo /var/ossec/bin/wazuh-control status
sudo tail -f /var/ossec/logs/ossec.log
```

### Usare Wazuh via CLI (modo corretto su RPi)

Esempi:

```bash
sudo /var/ossec/bin/agent_control -l
sudo /var/ossec/bin/list_agents -l
sudo /var/ossec/bin/wazuh-logtest
```

---

## Cosa sta già monitorando Wazuh (sul Raspberry)

Anche senza dashboard, Wazuh sta già lavorando

### File Integrity Monitoring (FIM)

Controlla modifiche a file critici:

```bash
/etc
/usr/bin
/usr/sbin
/bin
/sbin
```

Ad esempio, se qualcuno modifica /etc/passwd, Wazuh lo rileva.

Verifica:

```bash
sudo grep -i integrity /var/ossec/logs/ossec.log | tail
```

### Log Analysis

Sta leggendo automaticamente:

```bash
/var/log/auth.log (login SSH)
/var/log/syslog
/var/log/dpkg.log
```

Esempio pratico:

```bash
sudo grep -i ssh /var/ossec/logs/ossec.log | tail
```

Tentativi SSH falliti → allarme.

### Rootcheck (rilevamento malware/rootkit)

Controlla:

- binari sospetti
- permessi strani
- file nascosti

```bash
sudo tail -n 50 /var/ossec/logs/rootcheck.log
```

### Processi e porte sospette

Controlla:

- processi in esecuzione
- porte aperte
- escalation di privilegi

``` bash
sudo grep -i process /var/ossec/logs/ossec.log | tail
```

### Stato interno di Wazuh

```bash
sudo /var/ossec/bin/wazuh-control status
```

Devi vedere:

```bash
wazuh-analysisd is running
wazuh-logcollector is running
wazuh-syscheckd is running
```

---

## Installare Wazuh Indexer & Dashboard

Attenzione: queste non sono ufficialmente supportati, e, oltre a richiedere molte risorse, sono anche molto instabili per l'architettura `aarch64`

Procediamo a installare Wazuh Indexer + Dashboard direttamente sul tuo Raspberry Pi, senza Docker.

### Aggiungi il repository Wazuh

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor -o /usr/share/keyrings/wazuh-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh-archive-keyring.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt update
```

### Installa Wazuh Indexer (OpenSearch)

```bash
sudo apt install wazuh-indexer -y
```

### Installa Wazuh Dashboard

```bash
sudo apt install wazuh-dashboard -y
```

Controlla:

```bash
sudo nano /etc/wazuh-dashboard/opensearch_dashboards.yml
```

Deve essere come segue:

```bash
server.host: 0.0.0.0
server.port: 5601
server.ssl.enabled: false

opensearch.hosts: http://localhost:9200
opensearch.requestHeadersAllowlist: ["securitytenant","Authorization"]
opensearch_security.multitenancy.enabled: false
opensearch_security.readonly_mode.roles: ["kibana_read_only"]
uiSettings.overrides.defaultRoute: /app/wz-home
# Session expiration settings
opensearch_security.cookie.ttl: 900000
opensearch_security.session.ttl: 900000
opensearch_security.session.keepalive: true
```

### Avvia e abilita i servizi

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-indexer
sudo systemctl enable --now wazuh-dashboard
```

Verifica che siano attivi:

```bash
sudo systemctl status wazuh-indexer
sudo systemctl status wazuh-dashboard
```

### Configura Wazuh Manager per connettersi all’Indexer

Apri il file di configurazione del manager:

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Trova (o aggiungi) la sezione `<elasticsearch>` e modifica così:

```bash
<elasticsearch>
  <enabled>yes</enabled>
  <host>http://127.0.0.1:9200</host>
  <user>wazuh</user>
  <password>wazuh_password</password>
</elasticsearch>
```

Per ora useremo `user/password` di default. Poi li cambiamo.

Salva e chiudi, poi riavvia il manager:

```bash
sudo systemctl restart wazuh-manager
```

### Testa la connessione

Controlla i log:

```bash
sudo tail -f /var/ossec/logs/ossec.log
```

Dovresti vedere `IndexerConnector` initialized successfully.

### Accedi alla Dashboard

Apri nel browser:

```bash
http://IP_DEL_PI:5601
```

Credenziali di default:

```bash
user: admin
password: admin
```

Dopo il primo login, cambia subito la password.

---

## Rimozione Wazuh Indexer & Dashboard

Questa è la procedura completa per rimuovere tutto ciò che riguarda Wazuh Dashboard e Indexer e lasciare solo il Wazuh Manager funzionante sul Raspberry Pi aarch64

### Ferma e disabilita i servizi Dashboard e Indexer

```bash
sudo systemctl stop wazuh-dashboard wazuh-indexer
sudo systemctl disable wazuh-dashboard wazuh-indexer
```

### Rimuovi i pacchetti

```bash
sudo apt remove --purge wazuh-dashboard wazuh-indexer -y
sudo apt autoremove -y
```

### Cancella i file e directory residui

```bash
sudo rm -rf /etc/wazuh-dashboard
sudo rm -rf /var/lib/wazuh-dashboard
sudo rm -rf /usr/share/wazuh-dashboard

sudo rm -rf /usr/share/wazuh-indexer
sudo rm -rf /var/lib/wazuh-indexer
sudo rm -rf /etc/wazuh-indexer
```

Questo elimina completamente ogni traccia dei due componenti problematici.

## Verifica che rimanga solo il Manager

```bash
sudo systemctl status wazuh-manager
```

Deve risultare attivo (running).

Se non è attivo:

```bash
sudo systemctl enable --now wazuh-manager
sudo systemctl restart wazuh-manager
```

### Pulizia dei log

Se vuoi pulire i log residui di Dashboard/Indexer:

```bash
sudo rm -f /var/ossec/logs/wazuh-dashboard.log
sudo rm -f /var/ossec/logs/wazuh-indexer.log
```

### Test funzionalità del Manager

Puoi fare un semplice test:

```bash
sudo /var/ossec/bin/wazuh-control status
```

Dovresti vedere tutti i demoni essenziali attivi:

```bash
wazuh-modulesd
wazuh-syscheckd
wazuh-logcollector
wazuh-analysisd
ecc.
```

Puoi anche fare un test di monitoraggio creando un file di prova:

```bash
sudo touch /etc/test-wazuh
sudo tail -f /var/ossec/logs/ossec.log
```

Dovresti vedere che `wazuh-syscheckd` rileva la nuova creazione del file.