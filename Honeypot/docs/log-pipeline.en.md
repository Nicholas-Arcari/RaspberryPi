>  [Italiano](log-pipeline.md) |  **English**

# Walk-through: From Log Line to Dashboard Alert

Here is the complete path of an event, from the moment Cowrie writes it to when it appears as an alert:

## Phase 1: Cowrie Writes the Log

```
Cowrie --> /home/pi/cowrie/var/log/cowrie/cowrie.json
         (one new JSON line per event)
```

## Phase 2: Wazuh Agent Reads the File

The directive in `ossec.conf` tells the agent to monitor that file:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/home/pi/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>
```

The agent uses `inotify` (or polling) on the file. When a new line appears, it reads it and sends it to the Manager on port **1514/TCP**, encrypted with Wazuh's AES protocol.

## Phase 3: The Manager's JSON Decoder

The Manager receives the raw event. The built-in `json` decoder identifies the format as JSON and automatically extracts every field as a variable:

```
Raw event: {"eventid":"cowrie.login.success","username":"root",...}
                              | JSON decoder
Extracted fields:
  eventid    = "cowrie.login.success"
  username   = "root"
  password   = "12345"
  src_ip     = "203.0.113.45"
  ...
```

The extracted fields become available to the **rule engine**.

## Phase 4: The Rule Engine Matches Against Rules

The engine evaluates rules in `rule id` order. The `eventid` field matches parent rule 100010 (contains `cowrie.`), then child rule 100012 verifies `eventid == cowrie.login.success`:

```
Rule 100010 (level 3): eventid match "^cowrie\." --> MATCH (parent)
Rule 100012 (level 10): if_sid 100010 AND eventid == "cowrie.login.success" --> MATCH
--> Generates alert with level 10
```

## Phase 5: Alert Generated

The Manager writes the alert to `/var/ossec/logs/alerts/alerts.json`:

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

## Phase 6: Filebeat --> Indexer --> Dashboard

Filebeat reads `alerts.json`, sends it to the Indexer (OpenSearch) which indexes it into `wazuh-alerts-4.x-2026.03.15`. The Dashboard makes it visible in the **Threat Hunting** section where you can filter by `rule.id: 100012` or `data.src_ip: 203.0.113.45`.

## Rule Validation with wazuh-logtest

Before applying rules in production, test them with `wazuh-logtest`:

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Paste a Cowrie JSON line and verify that the correct rule matches. Expected output:

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

If Phase 3 does not show the expected rule, verify that the `eventid` field in the JSON matches exactly the one in the rule.
