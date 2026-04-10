# Guida all'installazione di Wazuh su Raspberry Pi 5 (ARM64)

Installazione manuale dei pacchetti `.deb` ARM64 dal repository Wazuh. Lo script automatico (`wazuh-install.sh`) non supporta ARM64.

---

## Step 1: Preparazione repository (ARM64)

```bash
sudo apt update && sudo apt install gnupg apt-transport-https -y
```

### Importazione chiave GPG

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && sudo chmod 644 /usr/share/keyrings/wazuh.gpg
```

**Cosa fa:** Scarica la chiave pubblica GPG di Wazuh e la salva in un keyring dedicato. APT usera' questa chiave per verificare l'autenticita' dei pacchetti scaricati dal repository Wazuh - se un pacchetto e' stato manomesso, la firma non corrisponde e l'installazione viene bloccata.

Il `chmod 644` e' necessario perche' `gpg` crea il file con permessi restrittivi, ma APT ha bisogno di leggerlo come utente non-root.

### Aggiunta del repository

```bash
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg arch=arm64] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
```

**Il parametro critico e' `arch=arm64`.** Senza di esso, APT tenta di scaricare pacchetti `amd64` che non sono installabili su ARM.

```bash
sudo apt update
```

---

## Step 2: Installazione dei componenti

```bash
sudo apt install wazuh-indexer wazuh-manager wazuh-dashboard -y
```

Questo installa i tre componenti principali direttamente sull'host (non in container Docker). L'installazione richiede diversi minuti.

---

## Step 3: Generazione e distribuzione certificati SSL

Wazuh usa comunicazione TLS/SSL tra tutti i componenti. Per capire nel dettaglio come funziona TLS, mTLS e i certificati X.509, vedi il [deep dive TLS/PKI](tls-pki.md).

### Download del tool di generazione certificati

```bash
curl -sO https://packages.wazuh.com/4.9/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/4.9/config.yml
```

### Configurazione

Editare `config.yml` impostando tutti gli IP dei nodi su `127.0.0.1` (setup All-in-One - tutti i servizi girano sulla stessa macchina):

```yaml
nodes:
  indexer:
    - name: node-1
      ip: 127.0.0.1
  server:
    - name: node-1
      ip: 127.0.0.1
  dashboard:
    - name: node-1
      ip: 127.0.0.1
```

### Generazione

```bash
sudo bash ./wazuh-certs-tool.sh -A
```

Il flag `-A` genera tutti i certificati in una volta. Vengono creati nella directory `wazuh-certificates/`:

- `node-1.pem` / `node-1-key.pem`: coppia certificato + chiave privata
- `root-ca.pem` / `root-ca-key.pem`: Certificate Authority (CA) root

### Distribuzione certificati a ogni componente

Ogni componente ha bisogno del certificato, della chiave privata e del CA root nella propria directory:

```bash
# Wazuh Indexer
sudo mkdir -p /etc/wazuh-indexer/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-indexer/certs/indexer.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-indexer/certs/indexer-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-indexer/certs/
sudo chmod 500 /etc/wazuh-indexer/certs
sudo chmod 400 /etc/wazuh-indexer/certs/*
sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs

# Wazuh Manager
sudo mkdir -p /etc/wazuh-manager/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-manager/certs/server.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-manager/certs/server-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-manager/certs/
sudo chmod 500 /etc/wazuh-manager/certs
sudo chmod 400 /etc/wazuh-manager/certs/*
sudo chown -R wazuh:wazuh /etc/wazuh-manager/certs

# Wazuh Dashboard
sudo mkdir -p /etc/wazuh-dashboard/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-dashboard/certs/dashboard.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-dashboard/certs/dashboard-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-dashboard/certs/
sudo chmod 500 /etc/wazuh-dashboard/certs
sudo chmod 400 /etc/wazuh-dashboard/certs/*
sudo chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/certs

# Filebeat
sudo mkdir -p /etc/filebeat/certs
sudo cp wazuh-certificates/node-1.pem /etc/filebeat/certs/filebeat.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/filebeat/certs/filebeat-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/filebeat/certs/
sudo chmod 500 /etc/filebeat/certs
sudo chmod 400 /etc/filebeat/certs/*
sudo chown -R root:root /etc/filebeat/certs
```

**Perche' `chmod 400` e `chmod 500`:**

- `400` sui file: solo il proprietario puo' leggere. La chiave privata non deve MAI essere leggibile da altri utenti
- `500` sulla directory: solo il proprietario puo' leggere e attraversare la directory

Se i permessi sono sbagliati, i servizi non partono con errore "Permission denied" sui file `.pem`.

---

## Step 4: Configurazione Dashboard

Editare `/etc/wazuh-dashboard/opensearch_dashboards.yml`:

```yaml
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

**Spiegazione parametri chiave:**

- `server.host: 0.0.0.0` - ascolta su tutte le interfacce (raggiungibile dalla rete, non solo localhost)
- `server.port: 443` - HTTPS standard. Richiede privilegi root o `cap_add NET_BIND_SERVICE` (le porte < 1024 sono privilegiate)
- `opensearch.ssl.verificationMode: none` - in un setup All-in-One con certificati self-signed, la verifica del certificato fallisce perche' il CA non e' "trusted". In produzione si userebbe `full`
- `opensearch.password: "admin"` - password di default. Viene cambiata con l'init di sicurezza (Step 5)

---

## Step 5: Avvio e inizializzazione

### Avvio dell'Indexer e init di sicurezza

```bash
sudo systemctl enable wazuh-indexer
sudo systemctl start wazuh-indexer

# Attendere ~30 secondi che OpenSearch si inizializzi completamente
sleep 30

# Inizializzazione del security plugin (crea utenti admin, configura RBAC)
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
```

Output atteso: `Done with success`

Questo script:

1. Carica la configurazione di sicurezza nell'indice `.opendistro_security`
2. Crea l'utente `admin` con la password configurata
3. Abilita TLS per tutte le comunicazioni interne

### Avvio Manager e Dashboard

```bash
sudo systemctl enable wazuh-manager
sudo systemctl start wazuh-manager

sudo systemctl enable wazuh-dashboard
sudo systemctl start wazuh-dashboard
```

La Dashboard sara' raggiungibile su: `https://<IP_RASPBERRY>:443`

Credenziali di default: `admin` / `admin`

![Portainer - Creazione dello stack Wazuh tramite Docker Compose nell'interfaccia web](../img/portainer-wazuh-stack.jpg)
