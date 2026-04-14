>  [English](log-pipeline.en.md) |  **Italiano**

# Walk-through: dalla riga di log all'alert sulla Dashboard

Ecco il percorso completo di un evento, dal momento in cui Cowrie lo scrive fino a quando appare come alert:

## Fase 1: Cowrie scrive il log

```
Cowrie → /home/pi/cowrie/var/log/cowrie/cowrie.json
         (una nuova riga JSON per ogni evento)
```

## Fase 2: Wazuh Agent legge il file

La direttiva in `ossec.conf` dice all'agente di monitorare quel file:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/home/pi/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>
```

L'agente fa `inotify` (o polling) sul file. Quando una nuova riga appare, la legge e la invia al Manager sulla porta **1514/TCP**, cifrata con il protocollo AES di Wazuh.

## Fase 3: il Decoder JSON del Manager

Il Manager riceve l'evento grezzo. Il decoder `json` (built-in) identifica che il formato è JSON e estrae automaticamente ogni campo come variabile:

```
Evento grezzo: {"eventid":"cowrie.login.success","username":"root",...}
                              ↓ decoder JSON
Campi estratti:
  eventid    = "cowrie.login.success"
  username   = "root"
  password   = "12345"
  src_ip     = "203.0.113.45"
  ...
```

I campi estratti diventano disponibili per il **rule engine**.

## Fase 4: il Rule Engine confronta con le regole

Il motore valuta le regole nell'ordine di `rule id`. Il campo `eventid` fa match con la regola padre 100010 (contiene `cowrie.`), poi la regola figlia 100012 verifica `eventid == cowrie.login.success`:

```
Regola 100010 (level 3): eventid match "^cowrie\." → MATCH (parent)
Regola 100012 (level 10): if_sid 100010 AND eventid == "cowrie.login.success" → MATCH
→ Genera alert con level 10
```

## Fase 5: Alert generato

Il Manager scrive l'alert in `/var/ossec/logs/alerts/alerts.json`:

```json
{
  "timestamp": "2026-03-15T14:32:07.892+0000",
  "rule": {
    "level": 10,
    "description": "Cowrie: INTRUSIONE RIUSCITA - Un attaccante è entrato nell'Honeypot",
    "id": "100012",
    "mitre": {
      "id": ["T1078"],
      "tactic": ["Defense Evasion", "Persistence", "Privilege Escalation", "Initial Access"],
      "technique": ["Valid Accounts"]
    },
    "groups": ["authentication_success", "pci_dss_10.2.5"]
  },
  "agent": {
    "id": "000",
    "name": "raspberrypi"
  },
  "data": {
    "eventid": "cowrie.login.success",
    "username": "root",
    "password": "12345",
    "src_ip": "203.0.113.45",
    "src_port": "48291",
    "dst_port": "2222",
    "session": "a]8f2e1c4b5d"
  },
  "location": "/home/pi/cowrie/var/log/cowrie/cowrie.json"
}
```

## Fase 6: Filebeat → Indexer → Dashboard

Filebeat legge `alerts.json`, lo invia all'Indexer (OpenSearch) che lo indicizza in `wazuh-alerts-4.x-2026.03.15`. La Dashboard lo rende visibile nella sezione **Threat Hunting** dove puoi filtrare per `rule.id: 100012` o `data.src_ip: 203.0.113.45`.

## Validazione delle regole con wazuh-logtest

Prima di applicare le regole in produzione, testarle con `wazuh-logtest`:

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Incollare una riga JSON di Cowrie e verificare che la regola corretta faccia match. Output atteso:

```
**Phase 1: Completed pre-decoding.
**Phase 2: Completed decoding.
       name: 'json'
**Phase 3: Completed filtering (rules).
       id: '100012'
       level: '10'
       description: 'Cowrie: INTRUSIONE RIUSCITA - Un attaccante è entrato nell'Honeypot'
       groups: '['local', 'syslog', 'sshd', 'authentication_success', 'pci_dss_10.2.5']'
```

Se la Phase 3 non mostra la regola attesa, verificare che il campo `eventid` nel JSON corrisponda esattamente a quello nella regola.
