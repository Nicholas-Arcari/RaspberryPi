# Honeypot - Cowrie SSH/Telnet con integrazione Wazuh SIEM

Un progetto di cybersecurity per trasformare il Raspberry Pi in una "trappola" (Honeypot) capace di attirare attaccanti, registrare le loro azioni e analizzarle in tempo reale tramite un SIEM. Include la configurazione completa, le regole custom per Wazuh, e tutti i problemi che ho incontrato con le relative soluzioni.

## Architettura

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

## Indice

| # | Sezione | Descrizione |
|---|---------|-------------|
| 1 | [Teoria: Cos'e' un Honeypot](docs/teoria-honeypot.md) | Classificazione degli honeypot, descrizione di Cowrie, mapping MITRE ATT&CK |
| 2 | [Installazione Cowrie + Wazuh](docs/installazione-cowrie.md) | Architettura, prerequisiti, setup Docker, configurazione ossec.conf, fix permessi |
| 3 | [Regole Custom Wazuh](docs/regole-wazuh.md) | local_rules.xml, spiegazione delle regole, esempio reale di log JSON Cowrie |
| 4 | [Pipeline: dal log all'alert](docs/log-pipeline.md) | Walk-through completo Fasi 1-6, validazione con wazuh-logtest |
| 5 | [Alternative a Cowrie](docs/alternative.md) | Tabella confronto honeypot, installazione OpenCanary e Dionaea, honeypot robots.txt, Q&A per analisti |
| 6 | [Troubleshooting + Test Finale](docs/troubleshooting.md) | 4 errori risolti con esperienza personale, test end-to-end del sistema |

## Test Finale (riassunto)

Per verificare il funzionamento end-to-end:

1. **Brute force** - `ssh -p 2222 root@<IP_RASPBERRY>` con password a caso → alert rule 100011
2. **Intrusione** - Password debole (`root`, `12345`) → alert rule 100012 (livello 10, critico)
3. **Post-exploitation** - Comandi come `whoami`, `cat /etc/shadow`, `wget` → alert rule 100013
4. **Dashboard** - Filtrare per `rule.id: 100012` o `rule.mitre.id: T1078` in Threat Hunting

Dettagli completi nella sezione [Troubleshooting + Test Finale](docs/troubleshooting.md).

---

Prossimo step: [SOC Analyst / Wazuh](../SOC%20Analyst/) - installazione e configurazione del SIEM Wazuh.
