>  [English](log-pipeline.en.md) |  **Italiano**

# Log Pipeline: il flusso dei dati dalla sorgente alla Dashboard

Capire come i log viaggiano dalla sorgente all'alert visualizzato sulla dashboard è essenziale per diagnosticare problemi ("perchè non vedo questo evento?") e per progettare nuove integrazioni.

```
SORGENTI                    RACCOLTA              ELABORAZIONE           STORAGE            VISUALIZZAZIONE
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

## Le 6 fasi del pipeline in dettaglio

**Fase 1 - Raccolta (Agent)**: Il demone `ossec-logcollector` sull'agente monitora i file di log configurati in `ossec.conf` (sezione `<localfile>`). Usa `inotify` per rilevare nuove righe in tempo reale (non polling periodico, quindi latenza quasi zero). I log vengono compressi con zlib e cifrati con AES-256-CBC prima dell'invio al Manager.

**Fase 2 - Decodifica (Manager)**: Il demone `ossec-analysisd` riceve gli eventi e li passa attraverso i **decoder** - regex che estraggono campi strutturati dal testo grezzo. Esempio: dal testo `Failed password for root from 192.168.0.50 port 54321 ssh2`, il decoder SSH estrae `user=root`, `srcip=192.168.0.50`, `srcport=54321`.

**Fase 3 - Regole (Manager)**: I campi decodificati vengono confrontati con la **rule chain** - migliaia di regole ordinate per ID. Le regole possono essere atomiche ("se vedi X, alerta") o composite ("se vedi X più di 5 volte in 60 secondi, alerta"). Solo gli eventi che matchano una regola con livello >= 3 generano un alert.

**Fase 4 - Arricchimento (Manager)**: L'alert JSON viene arricchito con metadati: mapping MITRE ATT&CK, informazioni sull'agente, GeoIP dell'IP sorgente (se configurato), punteggio CVSS per vulnerabilità.

**Fase 5 - Indicizzazione (Filebeat → Indexer)**: Filebeat legge gli alert JSON da `/var/ossec/logs/alerts/alerts.json` e li invia all'Indexer (OpenSearch) via HTTPS con autenticazione TLS mutua. L'Indexer indicizza i campi per ricerche rapide e li archivia in indici giornalieri (`wazuh-alerts-4.x-2025.04.08`).

**Fase 6 - Visualizzazione (Dashboard)**: La Dashboard legge gli indici dall'Indexer e presenta gli alert in tempo reale con filtri, grafici temporali, e drill-down per campo.

## Dove si rompe (diagnostica)

| Sintomo | Fase rotta | Come verificare |
|---|---|---|
| Nessun alert sulla Dashboard | Qualsiasi | Partire dal fondo: l'indice esiste? Filebeat gira? Il Manager riceve eventi? |
| L'agente risulta "Disconnected" | Fase 1 | `sudo systemctl status wazuh-agent`, verificare porte 1514/1515 su UFW |
| L'evento arriva ma non genera alert | Fase 3 | Testare con `wazuh-logtest` - il log matcha una regola? Il livello è >= 3? |
| L'alert appare nei log ma non sulla Dashboard | Fase 5 | `sudo systemctl status filebeat`, controllare la connessione Filebeat → Indexer |
| Query sulla Dashboard non trova risultati | Fase 6 | Verificare il range temporale selezionato, controllare il nome dell'indice |
