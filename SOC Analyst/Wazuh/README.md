# Wazuh - SIEM & XDR su Raspberry Pi 5

Guida completa all'installazione di Wazuh All-in-One (Manager + Indexer + Dashboard) su Raspberry Pi 5 con architettura ARM64. Questa installazione **non** e' supportata ufficialmente da Wazuh - documento qui il processo manuale che ho seguito, gli errori incontrati e le soluzioni adottate.

---

## Teoria: Cos'e' Wazuh

**Wazuh** e' una piattaforma open-source di sicurezza che combina:

- **SIEM** (Security Information and Event Management): raccoglie log da molteplici sorgenti, li normalizza, li correla e genera alert
- **XDR** (Extended Detection and Response): estende il rilevamento oltre i log tradizionali, includendo endpoint protection, vulnerability assessment e compliance monitoring

### Componenti dell'architettura

| Componente | Ruolo | Tecnologia base | Risorse richieste |
|---|---|---|---|
| **Wazuh Manager** | Riceve eventi dagli agenti, li analizza con regole e decoder, genera alert | C, Python | Leggero (~200MB RAM) |
| **Wazuh Indexer** | Indicizza e archivia gli alert per ricerca e visualizzazione | OpenSearch (fork di Elasticsearch) | Pesante (~1-2GB RAM) |
| **Wazuh Dashboard** | Interfaccia web per visualizzare alert, threat hunting, compliance | OpenSearch Dashboards (fork di Kibana) | Moderato (~500MB RAM) |
| **Filebeat** | Trasporta gli alert dal Manager all'Indexer | Elastic Filebeat | Leggero (~100MB RAM) |
| **Wazuh Agent** | Installato su ogni endpoint da monitorare, raccoglie log e li invia al Manager | C | Minimo (~50MB RAM) |

### Il flusso dei dati

```
[Endpoint con Agent] ──events (1514/TCP)──→ [Wazuh Manager]
                                                │
                                    analisi con decoder + regole
                                                │
                                                ▼
                                        genera alert JSON
                                                │
                                    [Filebeat] legge gli alert
                                                │
                                                ▼
                                        [Wazuh Indexer (OpenSearch)]
                                        indicizza in wazuh-alerts-*
                                                │
                                                ▼
                                        [Wazuh Dashboard]
                                        visualizza e permette threat hunting
```

**Perche' Filebeat?** Il Manager scrive gli alert in file JSON su disco. Filebeat agisce da "corriere" - legge questi file, li formatta e li invia all'Indexer via HTTPS. Senza Filebeat, la Dashboard sarebbe vuota perche' l'Indexer non riceverebbe dati.

---

## La sfida: Wazuh su ARM64

Wazuh e' progettato per architetture **x86_64**. Su Raspberry Pi (aarch64/ARM64):

- Lo script di installazione automatico (`wazuh-install.sh`) **fallisce** con "Uncompatible system" - non riconosce ARM64
- I container Docker ufficiali sono compilati per `amd64`, non per `arm64` - causano errori `exec format error` all'avvio
- Anche forzando `platform: linux/amd64` nel Docker Compose, la limitata RAM e le differenze architetturali impediscono a OpenSearch di partire

**Soluzione adottata:** Installazione manuale dei pacchetti `.deb` ARM64 dal repository Wazuh, forzando l'architettura nel source list APT.

> **Nota sulle risorse:** Il Raspberry Pi 5 con 8GB di RAM ce la fa, ma e' al limite. Con Wazuh All-in-One + Docker + Cowrie + Pi-hole attivi contemporaneamente, l'utilizzo RAM si aggira intorno ai 6-7GB. I 4GB non sarebbero sufficienti - l'Indexer (OpenSearch) richiede almeno 1GB di heap Java.

---

## Guida all'installazione

### Step 1: Preparazione repository (ARM64)

```bash
sudo apt update && sudo apt install gnupg apt-transport-https -y
```

#### Importazione chiave GPG

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && sudo chmod 644 /usr/share/keyrings/wazuh.gpg
```

**Cosa fa:** Scarica la chiave pubblica GPG di Wazuh e la salva in un keyring dedicato. APT usera' questa chiave per verificare l'autenticita' dei pacchetti scaricati dal repository Wazuh - se un pacchetto e' stato manomesso, la firma non corrisponde e l'installazione viene bloccata.

Il `chmod 644` e' necessario perche' `gpg` crea il file con permessi restrittivi, ma APT ha bisogno di leggerlo come utente non-root.

#### Aggiunta del repository

```bash
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg arch=arm64] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
```

**Il parametro critico e' `arch=arm64`.** Senza di esso, APT tenta di scaricare pacchetti `amd64` che non sono installabili su ARM.

```bash
sudo apt update
```

### Step 2: Installazione dei componenti

```bash
sudo apt install wazuh-indexer wazuh-manager wazuh-dashboard -y
```

Questo installa i tre componenti principali direttamente sull'host (non in container Docker). L'installazione richiede diversi minuti.

### Step 3: Generazione e distribuzione certificati SSL

Wazuh usa comunicazione TLS/SSL tra tutti i componenti. In un setup All-in-One (tutto sullo stesso host), i certificati sono auto-firmati (self-signed), ma comunque necessari per la cifratura del trasporto.

#### Come funziona TLS e perche' serve a Wazuh

**TLS (Transport Layer Security)** e' il protocollo che cifra la comunicazione tra due endpoint. Quando Filebeat invia alert all'Indexer, il traffico passa su HTTPS (HTTP + TLS). Senza TLS, gli alert (che contengono IP, username, password honeypot) transiterebbero in chiaro sulla rete.

L'handshake TLS 1.2 (usato da Wazuh) si svolge cosi':

```
Filebeat (client)                                    Indexer (server)
       │                                                    │
       ├── ClientHello ───────────────────────────────────►│
       │   (versione TLS, cipher suite supportate,          │
       │    random_client)                                  │
       │                                                    │
       │◄── ServerHello ──────────────────────────────────┤
       │   (cipher suite scelta, random_server)             │
       │                                                    │
       │◄── Certificate ──────────────────────────────────┤
       │   (certificato X.509 del server: indexer.pem)      │
       │                                                    │
       │◄── CertificateRequest ───────────────────────────┤
       │   (richiesta del certificato CLIENT: mutual TLS)   │
       │                                                    │
       │   Il client VERIFICA il certificato del server:    │
       │   1. La firma e' valida? (verificata con root-ca)  │
       │   2. Il CN/SAN corrisponde all'hostname?           │
       │   3. Il certificato e' scaduto?                    │
       │   4. E' nella CRL (revocation list)?               │
       │                                                    │
       │── Certificate (filebeat.pem) ────────────────────►│
       │── ClientKeyExchange (pre-master secret cifrato    │
       │   con la chiave pubblica del server) ────────────►│
       │── CertificateVerify (firma del client) ──────────►│
       │                                                    │
       │   Entrambi derivano il master secret:              │
       │   master = PRF(pre_master, random_c, random_s)     │
       │   → 4 chiavi simmetriche (cifratura + MAC,         │
       │     una per direzione)                             │
       │                                                    │
       │── ChangeCipherSpec ──────────────────────────────►│
       │◄── ChangeCipherSpec ─────────────────────────────┤
       │                                                    │
       │◄═══ Traffico cifrato (alert JSON via HTTPS) ═════►│
```

#### Mutual TLS (mTLS): autenticazione bidirezionale

In un TLS "normale" (es. visitare https://google.com), solo il **server** presenta il certificato. Il client verifica che il server sia chi dice di essere, ma il server non verifica il client.

In Wazuh, si usa **mutual TLS (mTLS)**: anche il **client** (Filebeat, Agent) deve presentare un certificato firmato dalla stessa CA. Questo garantisce che:

- Solo Filebeat con un certificato valido puo' inviare dati all'Indexer
- Solo agenti con certificato valido possono comunicare con il Manager
- Un attaccante che intercetta il traffico non puo' iniettare alert fasulli (non ha il certificato)

#### Il certificato X.509: cosa contiene

Puoi ispezionare un certificato generato da Wazuh:

```bash
openssl x509 -in /etc/wazuh-indexer/certs/indexer.pem -text -noout
```

Output (campi chiave):

```
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 1234567890abcdef
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN = Wazuh Root CA            ← Chi ha firmato (la nostra CA self-signed)
        Validity
            Not Before: Jan  1 00:00:00 2025 GMT
            Not After : Jan  1 00:00:00 2035 GMT  ← Scadenza (10 anni di default)
        Subject: CN = node-1                   ← Identita' del certificato
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
            RSA Public-Key: (2048 bit)
        X509v3 extensions:
            X509v3 Subject Alternative Name:   ← SAN: IP/hostname validi
                IP Address:127.0.0.1
```

| Campo | Significato | Perche' conta |
|---|---|---|
| `Issuer` | La CA che ha firmato il certificato | Il client verifica che l'Issuer sia nel suo trust store (`root-ca.pem`) |
| `Subject (CN)` | Common Name - identita' del server | Deve corrispondere al nome con cui il client si connette |
| `SAN` | Subject Alternative Name - IP/hostname alternativi | Standard moderno: TLS verifica il SAN, non il CN. Se manca l'IP `127.0.0.1`, la connessione fallisce con "certificate verify failed" |
| `Validity` | Periodo di validita' | Un certificato scaduto viene rifiutato. Causa comune di "Wazuh non parte dopo un anno" |
| `Serial Number` | Identificativo univoco | Usato per la revocation (CRL/OCSP) |

#### Chain of Trust: come il client "si fida"

```
[Root CA] (root-ca.pem / root-ca-key.pem)
    │
    │  firma (con root-ca-key.pem)
    ▼
[Certificato Indexer] (indexer.pem)  ← contiene la firma della Root CA
[Certificato Manager] (server.pem)  ← contiene la firma della Root CA
[Certificato Dashboard] (dashboard.pem)
[Certificato Filebeat] (filebeat.pem)
```

Quando Filebeat si connette all'Indexer:
1. L'Indexer presenta `indexer.pem`
2. Filebeat legge il campo `Issuer: CN = Wazuh Root CA`
3. Filebeat cerca `Wazuh Root CA` nel suo trust store (`/etc/filebeat/certs/root-ca.pem`)
4. Verifica che la firma nel certificato sia stata prodotta dalla chiave privata della Root CA
5. Se la verifica passa → connessione accettata
6. Se fallisce → "certificate verify failed" e connessione rifiutata

> **Perche' self-signed va bene nel nostro caso:** In un ambiente pubblico (siti web), i certificati devono essere firmati da una CA riconosciuta (Let's Encrypt, DigiCert) perche' i browser hanno una lista pre-installata di CA fidate. Nel nostro lab, tutti i componenti sono sullo stesso host e controlliamo la distribuzione dei certificati - una CA self-signed e' sufficiente e non introduce rischi aggiuntivi.

**Errore comune:** Se dopo aver rigenerato i certificati un componente non parte, verificare che il `root-ca.pem` sia stato copiato in **tutte** le directory (`/etc/wazuh-indexer/certs/`, `/etc/filebeat/certs/`, etc.). Un solo componente con la vecchia CA cautera' errori TLS nella pipeline.

#### Download del tool di generazione certificati

```bash
curl -sO https://packages.wazuh.com/4.9/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/4.9/config.yml
```

#### Configurazione

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

#### Generazione

```bash
sudo bash ./wazuh-certs-tool.sh -A
```

Il flag `-A` genera tutti i certificati in una volta. Vengono creati nella directory `wazuh-certificates/`:

- `node-1.pem` / `node-1-key.pem`: coppia certificato + chiave privata
- `root-ca.pem` / `root-ca-key.pem`: Certificate Authority (CA) root

#### Distribuzione certificati a ogni componente

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

### Step 4: Configurazione Dashboard

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

### Step 5: Avvio e inizializzazione

#### Avvio dell'Indexer e init di sicurezza

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

#### Avvio Manager e Dashboard

```bash
sudo systemctl enable wazuh-manager
sudo systemctl start wazuh-manager

sudo systemctl enable wazuh-dashboard
sudo systemctl start wazuh-dashboard
```

La Dashboard sara' raggiungibile su: `https://<IP_RASPBERRY>:443`

Credenziali di default: `admin` / `admin`

![Portainer - Creazione dello stack Wazuh tramite Docker Compose nell'interfaccia web](img/portainer-wazuh-stack.jpg)

---

## Filebeat: il "Postino" dei log

### Perche' serve Filebeat

Un errore comune e' vedere la Dashboard funzionante ma vuota, con l'errore **"No template found"**. Questo accade perche' manca il componente che trasporta gli alert dal Manager all'Indexer.

Il Manager scrive gli alert in `/var/ossec/logs/alerts/alerts.json`. L'Indexer aspetta di ricevere dati via HTTPS sulla porta 9200. Filebeat fa da ponte.

### Installazione

```bash
sudo apt install filebeat -y
```

### Configurazione (`/etc/filebeat/filebeat.yml`)

Sostituire l'intero contenuto con:

```yaml
output.elasticsearch:
  hosts: ["127.0.0.1:9200"]
  protocol: https
  username: "admin"
  password: "admin"
  ssl.certificate_authorities: ["/etc/filebeat/certs/root-ca.pem"]
  ssl.certificate: "/etc/filebeat/certs/filebeat.pem"
  ssl.key: "/etc/filebeat/certs/filebeat-key.pem"
  ssl.verification_mode: none

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

**Parametri critici:**

- `output.elasticsearch`: nonostante il nome, punta all'Indexer (che e' un fork di Elasticsearch/OpenSearch)
- `setup.ilm.enabled: false`: **fondamentale**. ILM (Index Lifecycle Management) e' una feature di Elasticsearch che crea indici con naming pattern diverso da quello atteso da Wazuh. Se abilitato, Filebeat crea indici `filebeat-7.x-*` invece di `wazuh-alerts-*` e la Dashboard non li trova
- `ssl.verification_mode: none`: necessario con certificati self-signed

### Download del template e setup

```bash
# Scarica il template JSON che definisce la struttura degli indici Wazuh
sudo curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v4.9.2/extensions/elasticsearch/7.x/wazuh-template.json
sudo chmod 444 /etc/filebeat/wazuh-template.json

# Carica il template nell'Indexer
sudo filebeat setup --index-management

# Avvia Filebeat
sudo systemctl enable filebeat
sudo systemctl restart filebeat
```

### Verifica connessione

```bash
sudo filebeat test output
```

Output atteso:

```
elasticsearch: https://127.0.0.1:9200...
  parse url... OK
  connection... OK
  TLS... OK
  talk to server... OK
  version: 7.10.2
```

Se mostra `ERROR`, verificare certificati, password e stato dell'Indexer.

---

## Problemi riscontrati e soluzioni

### 1. Script automatico "Uncompatible system"

**Problema:** Lo script `wazuh-install.sh` bloccava l'installazione con errore "Uncompatible system" su Raspberry Pi OS.

**Causa:** Lo script controlla `/etc/os-release` e la lista di sistemi supportati non include Raspberry Pi OS (anche se e' Debian-based).

**Soluzione:** Abbandonato lo script a favore dell'installazione manuale tramite `apt` con repository forzato `arch=arm64`.

### 2. Permessi GPG "Permission denied"

**Problema:** Il comando `curl ... | gpg ...` dava "Permission denied".

**Causa:** La pipe `|` esegue il secondo comando con i permessi dell'utente corrente (non root). `gpg` tentava di scrivere in `/usr/share/keyrings/` che richiede privilegi root.

**Soluzione:** `curl ... | sudo gpg ...` - il `sudo` va sul secondo comando della pipe, non sul primo.

### 3. Dashboard "No template found"

**Problema:** La Dashboard era raggiungibile ma mostrava un errore rosso persistente e nessun dato.

**Causa:** Due possibilita':
- Filebeat non installato o non avviato
- ILM abilitato che creava indici con naming pattern sbagliato (`filebeat-7.x` invece di `wazuh-alerts-*`)

**Soluzione:** Installato Filebeat, disabilitato ILM (`setup.ilm.enabled: false`) e forzato il caricamento del template corretto con `filebeat setup --index-management`.

### 4. Servizi non partono - "Permission denied" sui certificati

**Problema:** `systemctl start wazuh-indexer` falliva. I log mostravano "Permission denied" sui file `.pem`.

**Causa:** I certificati erano stati copiati con i permessi dell'utente corrente. Il servizio `wazuh-indexer` gira come utente `wazuh-indexer` e non poteva leggere file di proprieta' `root`.

**Soluzione:** `chown` corretto per ogni componente e permessi restrittivi (`chmod 400` sui file, `chmod 500` sulle directory).

---

## Deep Dive: ossec.conf - il cuore della configurazione Wazuh

Il file `/var/ossec/etc/ossec.conf` controlla il comportamento dell'intero agente/manager. Ecco le sezioni piu' importanti con spiegazione dei parametri.

### Sezione `<syscheck>` - File Integrity Monitoring

```xml
<syscheck>
  <!-- Intervallo tra scan completi (in secondi). 43200 = 12 ore -->
  <frequency>43200</frequency>

  <!-- Calcola hash SHA-256 per ogni file monitorato -->
  <alert_new_files>yes</alert_new_files>

  <!-- Directory da monitorare. check_all abilita tutti i controlli -->
  <directories check_all="yes" realtime="yes">/etc</directories>
  <directories check_all="yes" realtime="yes">/usr/bin</directories>
  <directories check_all="yes" realtime="yes">/usr/sbin</directories>
  <directories check_all="yes">/boot</directories>

  <!-- File e directory da IGNORARE (troppo rumorosi) -->
  <ignore>/etc/mtab</ignore>
  <ignore>/etc/resolv.conf</ignore>
  <ignore type="sregex">.log$</ignore>

  <!-- Monitora cambiamenti di: hash, permessi, owner, size, timestamp -->
  <check_sha256>yes</check_sha256>
  <check_perm>yes</check_perm>
  <check_owner>yes</check_owner>
  <check_size>yes</check_size>
  <check_mtime>yes</check_mtime>
</syscheck>
```

**Parametri chiave:**

| Parametro | Significato | Impatto |
|---|---|---|
| `frequency` | Intervallo tra scan completi | Valori bassi = piu' CPU, rilevamento piu' rapido |
| `realtime="yes"` | Usa `inotify` del kernel per rilevamento istantaneo | Non aspetta lo scan periodico, ma genera piu' eventi |
| `check_sha256` | Calcola hash SHA-256 di ogni file | Se l'hash cambia, il file e' stato modificato - rileva anche modifiche che non cambiano timestamp |
| `alert_new_files` | Genera alert quando un file nuovo appare | Rileva dropper di malware che creano file in `/usr/bin` |
| `ignore` | Esclude file/pattern dal monitoraggio | Essenziale per ridurre i falsi positivi (log che ruotano, file temporanei) |

### Sezione `<rootcheck>` - Rilevamento rootkit

```xml
<rootcheck>
  <disabled>no</disabled>
  <frequency>43200</frequency>

  <!-- Database di signature rootkit noti -->
  <rootkit_files>/var/ossec/etc/shared/rootkit_files.txt</rootkit_files>
  <rootkit_trojans>/var/ossec/etc/shared/rootkit_trojans.txt</rootkit_trojans>

  <!-- Controlla anomalie nel filesystem (/dev, /proc) -->
  <check_dev>yes</check_dev>
  <check_sys>yes</check_sys>
  <check_pids>yes</check_pids>
  <check_ports>yes</check_ports>

  <!-- Controlla file nascosti -->
  <check_unixaudit>yes</check_unixaudit>
</rootcheck>
```

`rootcheck` cerca:
- **File noti di rootkit** (confronto con database di signature)
- **Processi nascosti**: confronta l'output di `/proc` con quello di `ps` - se un PID esiste in `/proc` ma non in `ps`, potrebbe essere un rootkit che nasconde processi
- **Porte nascoste**: confronta `ss`/`netstat` con `/proc/net/tcp` per trovare porte aperte non visibili
- **File con permessi anomali** in `/dev` (un classico nascondiglio per rootkit)

### Sezione `<localfile>` - Sorgenti di log

```xml
<!-- Log di autenticazione (SSH, sudo, su) -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/auth.log</location>
</localfile>

<!-- Log di sistema generico -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/syslog</location>
</localfile>

<!-- Log Cowrie honeypot (formato JSON) -->
<localfile>
  <log_format>json</log_format>
  <location>/home/pi/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>

<!-- Log Docker container (se montati sull'host) -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/docker.log</location>
</localfile>
```

**`log_format` determina il decoder usato:**
- `syslog`: decoder standard che estrae timestamp, hostname, program, message
- `json`: decoder JSON che estrae automaticamente tutti i campi come variabili
- `audit`: per log di `auditd` (formato key=value)
- `multi-line`: per log che si estendono su piu' righe

### Struttura di un alert nell'Indexer (OpenSearch)

Ogni alert viene indicizzato in un indice con naming pattern `wazuh-alerts-4.x-YYYY.MM.DD`. Ecco la struttura completa di un documento nell'indice:

```json
{
  "_index": "wazuh-alerts-4.x-2026.03.15",
  "_id": "a1b2c3d4e5f6",
  "_source": {
    "timestamp": "2026-03-15T14:32:07.892+0000",
    "rule": {
      "level": 10,
      "description": "Cowrie: INTRUSIONE RIUSCITA",
      "id": "100012",
      "mitre": {
        "id": ["T1078"],
        "tactic": ["Initial Access"],
        "technique": ["Valid Accounts"]
      },
      "firedtimes": 3,
      "mail": false,
      "groups": ["local", "syslog", "sshd", "authentication_success"],
      "pci_dss": ["10.2.5"],
      "gdpr": ["IV_32.2"]
    },
    "agent": {
      "id": "000",
      "name": "raspberrypi",
      "ip": "127.0.0.1"
    },
    "manager": {
      "name": "raspberrypi"
    },
    "data": {
      "eventid": "cowrie.login.success",
      "username": "root",
      "password": "12345",
      "src_ip": "203.0.113.45",
      "src_port": "48291",
      "dst_ip": "192.168.0.102",
      "dst_port": "2222",
      "session": "a8f2e1c4b5d",
      "protocol": "ssh"
    },
    "decoder": {
      "name": "json"
    },
    "location": "/home/pi/cowrie/var/log/cowrie/cowrie.json"
  }
}
```

**Campi utili per il threat hunting sulla Dashboard:**

| Campo | Query Wazuh Dashboard | Cosa trovi |
|---|---|---|
| `rule.id` | `rule.id: 100012` | Tutte le intrusioni nell'honeypot |
| `rule.level` | `rule.level >= 10` | Tutti gli alert critici |
| `data.src_ip` | `data.src_ip: 203.0.113.45` | Tutti gli eventi da un IP specifico |
| `rule.mitre.id` | `rule.mitre.id: T1078` | Tutti gli eventi mappati a una tecnica MITRE |
| `rule.pci_dss` | `rule.pci_dss: 10.2.5` | Tutti gli eventi rilevanti per PCI DSS compliance |
| `agent.name` | `agent.name: raspberrypi` | Tutti gli eventi da un agente specifico |
| `rule.firedtimes` | ordina per `rule.firedtimes` desc | Regole che si attivano piu' spesso (possibile attacco in corso) |

---

## Comandi utili per manutenzione

```bash
# Stato di tutti i servizi Wazuh
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard filebeat

# Test connessione Filebeat → Indexer
sudo filebeat test output

# Log del Manager (per debug regole e decoder)
sudo tail -f /var/ossec/logs/ossec.log

# Log dell'Indexer (per problemi di indicizzazione)
sudo journalctl -u wazuh-indexer -f

# Test regole in tempo reale
sudo /var/ossec/bin/wazuh-logtest

# Reset password admin (se necessario)
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
```

---

## Stato attuale del sistema

Il sistema e' pienamente operativo:

- **Dashboard**: raggiungibile via HTTPS su IP locale porta 443
- **Ingestione log**: Filebeat attivo, indici `wazuh-alerts-*` popolati
- **Agenti**: configurabili su qualsiasi endpoint (Windows/Linux/macOS) puntando all'IP del Raspberry porta 1514
- **Regole custom**: attive per Cowrie (rule ID 100010-100013)
- **FIM**: Syscheck monitora `/etc`, `/usr/bin` e altre directory critiche
