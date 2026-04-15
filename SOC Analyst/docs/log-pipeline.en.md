>  [Italiano](log-pipeline.md) |  **English**

# Log Pipeline: the data flow from source to Dashboard

Understanding how logs travel from their source to the alert displayed on the dashboard is essential for diagnosing problems ("why am I not seeing this event?") and for designing new integrations.

```
SOURCES                     COLLECTION            PROCESSING             STORAGE            VISUALIZATION
─────────────────────────────────────────────────────────────────────────────────────────────────────────
/var/log/auth.log  ──┐
/var/log/ufw.log   ──┤
/var/log/syslog    ──┤      Wazuh Agent          Wazuh Manager          Wazuh Indexer      Wazuh Dashboard
/var/log/fail2ban  ──┼──►  (ossec-logcollector  ──► (ossec-analysisd    ──► (OpenSearch     ──► (OpenSearch
/var/log/cowrie/   ──┤      inotify/polling)       decoder + rules)      Filebeat)           Dashboards)
Docker logs        ──┤
FIM (syscheck)     ──┘      Porta 1514/TCP        local_rules.xml        Indici             Query, filtri,
                             ▲                     local_decoder.xml      wazuh-alerts-*     grafici, report
                             │                          │                      │
                             │                          ▼                      ▼
                        Registrazione            Alert JSON              Retention policy
                        agenti: 1515/TCP         (livello ≥ 3)          (90 giorni default)
```

## The 6 pipeline phases in detail

**Phase 1 - Collection (Agent)**: The `ossec-logcollector` daemon on the agent monitors the log files configured in `ossec.conf` (the `<localfile>` section). It uses `inotify` to detect new lines in real time (not periodic polling, so latency is near zero). Logs are compressed with zlib and encrypted with AES-256-CBC before being sent to the Manager.

**Phase 2 - Decoding (Manager)**: The `ossec-analysisd` daemon receives events and passes them through **decoders** - regex patterns that extract structured fields from raw text. Example: from the text `Failed password for root from 192.168.0.50 port 54321 ssh2`, the SSH decoder extracts `user=root`, `srcip=192.168.0.50`, `srcport=54321`.

**Phase 3 - Rules (Manager)**: The decoded fields are compared against the **rule chain** - thousands of rules ordered by ID. Rules can be atomic ("if you see X, alert") or composite ("if you see X more than 5 times in 60 seconds, alert"). Only events matching a rule with level >= 3 generate an alert.

**Phase 4 - Enrichment (Manager)**: The JSON alert is enriched with metadata: MITRE ATT&CK mapping, agent information, source IP GeoIP (if configured), CVSS score for vulnerabilities.

**Phase 5 - Indexing (Filebeat -> Indexer)**: Filebeat reads the JSON alerts from `/var/ossec/logs/alerts/alerts.json` and sends them to the Indexer (OpenSearch) via HTTPS with mutual TLS authentication. The Indexer indexes the fields for fast searches and stores them in daily indices (`wazuh-alerts-4.x-2025.04.08`).

**Phase 6 - Visualization (Dashboard)**: The Dashboard reads the indices from the Indexer and presents the alerts in real time with filters, time-series charts, and per-field drill-down.

## Where it breaks (diagnostics)

| Symptom | Broken phase | How to verify |
|---|---|---|
| No alerts on the Dashboard | Any | Start from the bottom: does the index exist? Is Filebeat running? Is the Manager receiving events? |
| The agent shows as "Disconnected" | Phase 1 | `sudo systemctl status wazuh-agent`, verify ports 1514/1515 on UFW |
| The event arrives but does not generate an alert | Phase 3 | Test with `wazuh-logtest` - does the log match a rule? Is the level >= 3? |
| The alert appears in the logs but not on the Dashboard | Phase 5 | `sudo systemctl status filebeat`, check the Filebeat -> Indexer connection |
| Dashboard query returns no results | Phase 6 | Verify the selected time range, check the index name |
