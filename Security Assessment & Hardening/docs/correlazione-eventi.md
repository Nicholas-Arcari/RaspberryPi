>  [English](correlazione-eventi.en.md) |  **Italiano**

# Correlazione eventi e Test finale

## Test finale: verifica end-to-end

Per confermare che tutto funzionasse in uno scenario reale:

1. Ho scollegato il mio PC di test (Kali) dal Wi-Fi di casa
2. L'ho collegato all'**hotspot del cellulare** (simulando una rete esterna)
3. Ho lanciato la connessione SSH verso l'indirizzo Ngrok:

```bash
ssh root@<indirizzo_ngrok> -p <porta_ngrok>
```

4. L'accesso all'Honeypot è stato garantito
5. **Immediatamente** sulla Dashboard di Wazuh è scattato l'allarme "Intrusione Rilevata" (rule 100012, livello 10)

Il sistema è online, monitorato e funzionante.

---

## Alert Wazuh generato dall'intrusione

Questo è l'alert JSON reale (anonimizzato) che Wazuh ha generato nel momento in cui ho effettuato il login sull'Honeypot via Ngrok:

```json
{
  "_index": "wazuh-alerts-4.x-2025.XX.XX",
  "_id": "a3B7xZIBkQr8vN2f_example",
  "_source": {
    "rule": {
      "level": 10,
      "description": "Cowrie: Login success detected on honeypot",
      "id": "100012",
      "mitre": {
        "tactic": ["Initial Access", "Credential Access"],
        "technique": ["T1078 - Valid Accounts", "T1110 - Brute Force"],
        "id": ["T1078", "T1110"]
      },
      "groups": ["cowrie", "honeypot"]
    },
    "agent": {
      "id": "001",
      "name": "raspberrypi",
      "ip": "192.168.0.XXX"
    },
    "data": {
      "cowrie": {
        "eventid": "cowrie.login.success",
        "username": "root",
        "password": "12345",
        "src_ip": "XX.XX.XX.XX",
        "session": "a1b2c3d4e5f6",
        "protocol": "ssh",
        "timestamp": "2025-XX-XXT14:47:23.456789Z"
      }
    },
    "location": "/var/log/cowrie/cowrie.json",
    "timestamp": "2025-XX-XXT14:47:24.001Z",
    "manager": {
      "name": "wazuh-manager"
    },
    "full_log": "{\"eventid\":\"cowrie.login.success\",\"username\":\"root\",\"password\":\"12345\",\"src_ip\":\"XX.XX.XX.XX\",\"session\":\"a1b2c3d4e5f6\",\"protocol\":\"ssh\",\"timestamp\":\"2025-XX-XXT14:47:23.456789Z\"}"
  }
}
```

**Analisi dei campi chiave:**

| Campo | Valore | Significato |
|---|---|---|
| `rule.level` | `10` | Severità alta (scala 0-15). Livello 10 = attività sospetta che richiede attenzione immediata |
| `rule.id` | `100012` | Regola custom definita in `/var/ossec/etc/rules/local_rules.xml` sul Manager |
| `rule.mitre` | T1078, T1110 | Mapping automatico alle tecniche MITRE ATT&CK per contestualizzare l'attacco |
| `data.cowrie.src_ip` | `XX.XX.XX.XX` | IP sorgente dell'attaccante. In questo caso, l'IP pubblico dell'hotspot del cellulare (passato attraverso Ngrok) |
| `data.cowrie.password` | `12345` | Password usata - Cowrie registra **tutte** le credenziali tentate, utili per analisi statistica delle password più comuni |
| `data.cowrie.session` | `a1b2c3d4e5f6` | Identificativo univoco della sessione. Permette di correlare tutti gli eventi di una stessa sessione (login, comandi, download) |
| `location` | `/var/log/cowrie/cowrie.json` | File sorgente del log, monitorato dall'agente Wazuh tramite inotify |

---

## Correlazione eventi: dalla scansione all'alert

In un SOC reale, gli eventi non vengono analizzati in isolamento. La correlazione consiste nel collegare eventi apparentemente separati per ricostruire la **kill chain** dell'attaccante. Ecco come i diversi componenti del lab hanno registrato la mia simulazione:

### Timeline dell'attacco simulato

```
T+0s    Nmap SYN scan dalla macchina Kali
        +-- UFW log: 65535 SYN packets da 192.168.0.YYY (Kali)
        +-- Wazuh rule 5710 (livello 3): "Attempt to scan open ports"

T+30s   Hydra brute force sulla porta 2222
        +-- Cowrie log: centinaia di cowrie.login.failed in rapida successione
        +-- Wazuh rule 100011 (livello 5): "Cowrie: Multiple failed login attempts"

T+2m    Hydra trova password valida (root/12345)
        +-- Cowrie log: cowrie.login.success
        +-- Wazuh rule 100012 (livello 10): "Cowrie: Login success on honeypot"

T+2m30s Sessione interattiva: l'attaccante esegue comandi
        +-- Cowrie log: cowrie.command.input (cat /etc/passwd, wget, uname -a)
        +-- Wazuh rule 100013 (livello 8): "Cowrie: Command executed in honeypot"

T+3m    Tentativo di download malware (simulato)
        +-- Cowrie log: cowrie.session.file_download
        +-- Wazuh rule 100014 (livello 12): "Cowrie: File download attempt"
```

### Query di correlazione sulla Dashboard

Per ricostruire l'intera sequenza su Wazuh Dashboard (OpenSearch Dashboards), questa query filtra tutti gli eventi relativi a una singola sessione dell'attaccante:

```
data.cowrie.session: "a1b2c3d4e5f6" OR data.srcip: "XX.XX.XX.XX"
```

Ordinando per `timestamp` ascendente, si ottiene la timeline completa: dal primo tentativo di login fallito, al successo, ai comandi eseguiti nella sessione honeypot, fino all'eventuale download di file. Questo è esattamente il workflow che un analista SOC L1 seguirebbe durante il triage di un alert reale.

### Correlazione con i log di rete (UFW)

I log di UFW (`/var/log/ufw.log`) completano il quadro con il livello di rete:

```
[UFW BLOCK] IN=eth0 OUT= MAC=XX:XX:XX SRC=XX.XX.XX.XX DST=192.168.0.XXX LEN=44
            TOS=0x00 PREC=0x00 TTL=64 ID=54321 PROTO=TCP SPT=54321 DPT=9200
            WINDOW=1024 RES=0x00 SYN URGP=0
```

**Lettura del log UFW:**

| Campo | Significato |
|---|---|
| `[UFW BLOCK]` | Il pacchetto è stato bloccato (dopo la remediation) |
| `SRC=XX.XX.XX.XX` | IP sorgente dell'attaccante |
| `DPT=9200` | Porta di destinazione - l'attaccante ha tentato di raggiungere OpenSearch |
| `SYN` | Flag TCP - è il primo pacchetto di un handshake (scansione) |
| `WINDOW=1024` | Window size tipica di Nmap SYN scan (fingerprint del tool) |

La correlazione tra il `SRC` del log UFW e il `data.cowrie.src_ip` dell'alert Wazuh conferma che lo stesso IP ha prima scansionato le porte (bloccato da UFW su 9200) e poi si è concentrato sulla porta 2222 (Honeypot, aperta intenzionalmente).

> **Lezione da analista:** Un singolo alert non racconta mai la storia completa. La vera analisi inizia quando si correlano eventi da fonti diverse (firewall, honeypot, SIEM) per ricostruire l'intera catena d'attacco. Questo è il valore di avere un SIEM centralizzato come Wazuh: tutti i log convergono in un unico punto, rendendo la correlazione possibile.
