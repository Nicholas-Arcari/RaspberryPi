>  [English](confronto-siem.en.md) |  **Italiano**

# Perchè Wazuh e non Splunk (o altri SIEM)

La scelta del SIEM è una decisione architetturale critica. Wazuh non è stato scelto "perchè è gratis" - è stato scelto per ragioni tecniche specifiche al nostro caso d'uso.

## Confronto architetturale

| Aspetto | Wazuh | Splunk Enterprise | Splunk Free | Elastic SIEM |
|---|---|---|---|---|
| **Licenza** | Open source (GPLv2) | Commerciale (~$2000/GB/anno) | Gratuito, 500MB/giorno | Open source (SSPL) |
| **Costo per il nostro lab** | $0 | ~$15.000+/anno (impensabile) | $0 ma molto limitato | $0 |
| **ARM64 (Raspberry Pi)** | Pacchetti .deb ARM64 disponibili | **NON disponibile** su ARM | **NON disponibile** su ARM | Pacchetti ARM64 disponibili |
| **Agent integrato** | Si (FIM, rootcheck, vulnerability detection) | Universal Forwarder (solo log shipping) | Universal Forwarder | Elastic Agent |
| **IDS/IPS integrato** | Parziale (log analysis rules) | No (richiede add-on) | No | No |
| **Active Response** | Si (blocco IP automatico) | No nativo (richiede SOAR) | No | No nativo |
| **Compliance** | PCI DSS, GDPR, HIPAA, CIS | Si (con add-on a pagamento) | No | Parziale |
| **Storage backend** | OpenSearch (fork Elasticsearch) | Proprietario (Splunk indexes) | Proprietario | Elasticsearch |
| **Query language** | OpenSearch DSL (JSON) | SPL (Splunk Processing Language) | SPL | KQL / EQL |
| **Risorse su RPi 5 (8GB)** | ~4-5GB RAM totali | N/A (non gira su ARM) | N/A | ~3-4GB RAM |

## La motivazione reale

1. **ARM64**: Splunk semplicemente non gira su Raspberry Pi. Fine della discussione per il nostro hardware. Se avessimo un server x86_64 con 32GB di RAM, Splunk Enterprise sarebbe una scelta valida

2. **All-in-one**: Wazuh non è solo un SIEM - è anche un XDR. L'agent fa FIM, vulnerability detection, rootcheck, log collection e compliance in un unico pacchetto. Con Splunk, dovresti installare separatamente: Universal Forwarder + OSSEC/Tripwire (FIM) + Nessus/OpenVAS (vulnerability) + tool di compliance

3. **Active Response**: Wazuh può bloccare un IP automaticamente quando un alert raggiunge una certa soglia. Splunk richiede un SOAR separato (Splunk SOAR, ex Phantom) - un altro prodotto a pagamento

4. **Costo**: Per un home lab educativo, il costo di Splunk è proibitivo. Wazuh offre il 90% delle funzionalità a costo zero

## Se volessi migrare a Splunk (su hardware x86_64)

Le modifiche architetturali necessarie:

```
ATTUALE (Wazuh):
Agent → Manager :1514 → Filebeat → OpenSearch :9200 → Dashboard :443

SPLUNK:
Universal Forwarder → Splunk Indexer :9997 → Splunk Search Head :8000
                                       ↑
                              Splunk Heavy Forwarder
                              (parsing e filtering)
```

| Componente Wazuh | Sostituito da | Configurazione |
|---|---|---|
| Wazuh Agent | Splunk Universal Forwarder | `inputs.conf`: monitor dei log, `outputs.conf`: puntamento all'Indexer |
| Wazuh Manager (decoder + rules) | Splunk Heavy Forwarder + `props.conf`/`transforms.conf` | Regole di parsing (regex per estrarre campi), lookup tables per enrichment |
| OpenSearch (Indexer) | Splunk Indexer | `indexes.conf`: definizione indici, retention policy, volume di storage |
| Wazuh Dashboard | Splunk Search Head | Dashboard custom in Simple XML o Dashboard Studio |
| Filebeat | Non necessario | Il Forwarder invia direttamente all'Indexer |
| Regole custom (local_rules.xml) | Correlation searches + Notable events | SPL queries schedulati in Enterprise Security |
| Active Response | Splunk SOAR (Phantom) | Playbook automatici (prodotto separato, a pagamento) |

**File chiave da creare/modificare per Splunk:**

```ini
# inputs.conf (sul Forwarder - equivale a <localfile> in ossec.conf)
[monitor:///var/log/auth.log]
sourcetype = linux_secure
index = security

[monitor:///var/log/cowrie/cowrie.json]
sourcetype = cowrie:json
index = honeypot

# props.conf (parsing - equivale ai decoder Wazuh)
[cowrie:json]
KV_MODE = json
TIME_FORMAT = %Y-%m-%dT%H:%M:%S.%6N%Z
TIME_PREFIX = "timestamp":"

# savedsearches.conf (correlation - equivale alle regole Wazuh)
[Honeypot Login Success]
search = index=honeypot sourcetype=cowrie:json eventid=cowrie.login.success
alert_threshold = 1
action.email = 1
cron_schedule = */5 * * * *
```

> **Nota per chi studia:** In un colloquio per SOC analyst, saper spiegare le differenze architetturali tra Wazuh e Splunk (e quando usare l'uno o l'altro) è un punto a favore. Wazuh per lab/PMI con budget limitato e bisogno di agent integrati. Splunk per enterprise con budget, volumi di dati elevati e necessità di SPL per query complesse.
