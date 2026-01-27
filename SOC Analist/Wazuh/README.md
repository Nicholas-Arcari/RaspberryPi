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

## Guida all'installazione

### preparazione repository (ARM64)

Lo script automatico fallisce nel rilevare l'architettura. Abbiamo aggiunto manualmente il repo forzando l'architettura `arm64`

```bash
sudo apt update && sudo apt install gnupg apt-transport-https -y

# Importazione chiave GPG (con privilegi corretti)
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && sudo chmod 644 /usr/share/keyrings/wazuh.gpg

# Aggiunta Repository
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg arch=arm64] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list

sudo apt update
```

---

### Installazione Componenti

Installiamo i tre pilastri principali manualmente

```Bash
sudo apt install wazuh-indexer wazuh-manager wazuh-dashboard -y
```

---

### Generazione e Configurazione Certificati

Poiché l'installer automatico nel mio caso non ha funzionato, sono stati generati i certificati SSL manualmente

Scarica il tool:

```Bash
curl -sO https://packages.wazuh.com/4.9/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/4.9/config.yml
```

Edita `config.yml` impostando l'IP dei nodi su `127.0.0.1` (Setup All-in-One)

Genera i certificati:

```Bash
sudo bash ./wazuh-certs-tool.sh -A
```

Distribuisci i certificati (comandi eseguiti per ogni componente):

```Bash
# 1. Per Wazuh Indexer
sudo mkdir -p /etc/wazuh-indexer/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-indexer/certs/indexer.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-indexer/certs/indexer-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-indexer/certs/
sudo chmod 500 /etc/wazuh-indexer/certs
sudo chmod 400 /etc/wazuh-indexer/certs/*
sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs

# 2. Per Wazuh Manager
sudo mkdir -p /etc/wazuh-manager/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-manager/certs/server.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-manager/certs/server-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-manager/certs/
sudo chmod 500 /etc/wazuh-manager/certs
sudo chmod 400 /etc/wazuh-manager/certs/*
sudo chown -R wazuh:wazuh /etc/wazuh-manager/certs

# 3. Per Wazuh Dashboard
sudo mkdir -p /etc/wazuh-dashboard/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-dashboard/certs/dashboard.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-dashboard/certs/dashboard-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-dashboard/certs/
sudo chmod 500 /etc/wazuh-dashboard/certs
sudo chmod 400 /etc/wazuh-dashboard/certs/*
sudo chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/certs

# 4. Per Filebeat (Il postino)
sudo mkdir -p /etc/filebeat/certs
sudo cp wazuh-certificates/node-1.pem /etc/filebeat/certs/filebeat.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/filebeat/certs/filebeat-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/filebeat/certs/
sudo chmod 500 /etc/filebeat/certs
sudo chmod 400 /etc/filebeat/certs/*
sudo chown -R root:root /etc/filebeat/certs
```

---

### COnfigurazione DAshboard

È necessario configurare la Dashboard per raggiungere l'Indexer e accettare i certificati generati

Modificare il file `/etc/wazuh-dashboard/opensearch_dashboards.yml` sostituendo il contenuto con:

```YAML
server.host: 0.0.0.0
server.port: 443
opensearch.hosts: https://127.0.0.1:9200
opensearch.ssl.verificationMode: none
opensearch.username: "admin"
opensearch.password: "admin"
server.ssl.enabled: true
server.ssl.key: "/etc/wazuh-dashboard/certs/dashboard-key.pem"
server.ssl.certificate: "/etc/wazuh-dashboard/certs/dashboard.pem"
opensearch.ssl.certificateAuthorities: ["/etc/wazuh-dashboard/certs/root-ca.pem"]
uiSettings.overrides.defaultRoute: /app/wz-home
```


---

### Avvio e Inizializzazione Sicurezza

Avvio del database e caricamento delle credenziali (creazione utente admin)

```Bash
sudo systemctl enable wazuh-indexer
sudo systemctl start wazuh-indexer
# Attendere 30 secondi
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
```

Output atteso: `Done with success`

Successivamente avviare Manager e Dashboard:

```Bash
sudo systemctl start wazuh-manager
sudo systemctl start wazuh-dashboard
```

---

## Il "Postino": Configurazione Filebeat

Un errore comune è vedere la Dashboard funzionante ma vuota ("No template found").

Questo accade perché manca Filebeat, il componente che sposta i log dal Manager al Database

### Installazione

```Bash
sudo apt install filebeat -y
```

### Configurazione (`/etc/filebeat/filebeat.yml`)

Modificare il file `/etc/filebeat/filebeat.yml` sostituendo l'intero contenuto con il seguente blocco:

```YAML
output.elasticsearch:
  hosts: ["127.0.0.1:9200"]
  protocol: https
  username: "admin"
  password: "admin" # O la password generata se diversa
  ssl.certificate_authorities: ["/etc/filebeat/certs/root-ca.pem"]
  ssl.certificate: "/etc/filebeat/certs/filebeat.pem"
  ssl.key: "/etc/filebeat/certs/filebeat-key.pem"
  ssl.verification_mode: none # Necessario se i certificati non matchano perfettamente l'hostname

setup.template.json.enabled: true
setup.template.json.path: '/etc/filebeat/wazuh-template.json'
setup.template.json.name: 'wazuh'
setup.ilm.overwrite: true
setup.ilm.enabled: false

filebeat.modules:
  - module: wazuh
    alerts:
      enabled: true
    archives:
      enabled: false
```

Comandi correttivi eseguiti:

```Bash
# Scarica template JSON corretto
sudo curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v4.9.2/extensions/elasticsearch/7.x/wazuh-template.json
sudo chmod 444 /etc/filebeat/wazuh-template.json

# Setup del template nel database
sudo filebeat setup --index-management

# Riavvio
sudo systemctl restart filebeat
```

---

## Problemi Riscontrati & Risoluzione

1. Errore Script "Uncompatible system"

- Problema: Lo script `wazuh-install.sh` bloccava l'installazione su Raspberry Pi OS
- Soluzione: Abbandonato lo script automatico a favore dell'installazione manuale tramite `apt` con repository forzato `arch=arm64`

2. Permessi GPG

- Problema: `curl ... | gpg ...` dava "Permission denied"
- Causa: La pipe `|` eseguiva il secondo comando come utente normale
- Soluzione: Aggiunto sudo esplicito dopo la pipe: `curl ... | sudo gpg ...`

3. Errore Dashboard "No template found"

- Problema: Accesso alla Dashboard possibile, ma errore rosso persistente e nessun dato visibile
- Causa: Filebeat non configurato o ILM attivo che creava indici errati (`filebeat-7.x` invece di `wazuh-alerts-*`)
- Soluzione: Disabilitato ILM nel config e lanciato `filebeat setup --index-management`

4. Permessi Certificati

- Problema: I servizi non partivano ("Permission denied" sui file `.pem`)
- Soluzione: Uso di `chmod 500` sulle cartelle e `chmod 400` sui file, assicurandosi di assegnare il proprietario corretto (`chown wazuh:wazuh`, etc.)

---

## Stato Attuale

Il sistema è pienamente operativo.

- Dashboard: Raggiungibile via HTTPS su IP locale
- Log: Ingestione attiva da Filebeat
- Agenti: Configurabili su Windows/Linux puntando all'IP del Raspberry

### Comandi Utili per Manutenzione

Verifica stato servizi:

```Bash
sudo systemctl status wazuh-indexer
sudo systemctl status wazuh-manager
sudo systemctl status wazuh-dashboard
sudo systemctl status filebeat
```

Test output Filebeat (Debug connessione):

```Bash
sudo filebeat test output
```

Reset Password Admin: Se necessario, utilizzare `wazuh-passwords-tool.sh` o reinstallare la security tramite `indexer-security-init.sh`