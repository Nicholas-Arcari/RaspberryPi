>  [English](README.en.md) |  **Italiano**

# Wazuh - SIEM & XDR su Raspberry Pi 5

Guida completa all'installazione di Wazuh All-in-One (Manager + Indexer + Dashboard) su Raspberry Pi 5 con architettura ARM64. Questa installazione **non** è supportata ufficialmente da Wazuh - documento qui il processo manuale che ho seguito, gli errori incontrati e le soluzioni adottate.

---

## Teoria: Cos'è Wazuh

**Wazuh** è una piattaforma open-source di sicurezza che combina:

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
[Endpoint con Agent] --events (1514/TCP)--> [Wazuh Manager]
                                                |
                                    analisi con decoder + regole
                                                |
                                                v
                                        genera alert JSON
                                                |
                                    [Filebeat] legge gli alert
                                                |
                                                v
                                        [Wazuh Indexer (OpenSearch)]
                                        indicizza in wazuh-alerts-*
                                                |
                                                v
                                        [Wazuh Dashboard]
                                        visualizza e permette threat hunting
```

**Perchè Filebeat?** Il Manager scrive gli alert in file JSON su disco. Filebeat agisce da "corriere" - legge questi file, li formatta e li invia all'Indexer via HTTPS. Senza Filebeat, la Dashboard sarebbe vuota perchè l'Indexer non riceverebbe dati.

---

## La sfida: Wazuh su ARM64

Wazuh è progettato per architetture **x86_64**. Su Raspberry Pi (aarch64/ARM64):

- Lo script di installazione automatico (`wazuh-install.sh`) **fallisce** con "Uncompatible system" - non riconosce ARM64
- I container Docker ufficiali sono compilati per `amd64`, non per `arm64` - causano errori `exec format error` all'avvio
- Anche forzando `platform: linux/amd64` nel Docker Compose, la limitata RAM e le differenze architetturali impediscono a OpenSearch di partire

**Soluzione adottata:** Installazione manuale dei pacchetti `.deb` ARM64 dal repository Wazuh, forzando l'architettura nel source list APT.

> **Nota sulle risorse:** Il Raspberry Pi 5 con 8GB di RAM ce la fa, ma è al limite. Con Wazuh All-in-One + Docker + Cowrie + Pi-hole attivi contemporaneamente, l'utilizzo RAM si aggira intorno ai 6-7GB. I 4GB non sarebbero sufficienti - l'Indexer (OpenSearch) richiede almeno 1GB di heap Java.

---

## Indice della documentazione

| Documento | Contenuto |
|---|---|
| [Guida all'installazione](docs/installazione.md) | Step 1-5: repository ARM64, componenti, certificati SSL, dashboard, avvio |
| [Deep Dive: TLS/PKI](docs/tls-pki.md) | Handshake TLS 1.2, mutual TLS, certificati X.509, chain of trust |
| [Filebeat](docs/filebeat.md) | Installazione, configurazione, template, verifica connessione |
| [Deep Dive: ossec.conf](docs/ossec-conf.md) | Syscheck (FIM), rootcheck, localfile, struttura alert JSON |
| [Suricata IDS/IPS](docs/suricata.md) | Network IDS, regole ET Open, integrazione con Wazuh |
| [Rules Best Practices](docs/rules-best-practices.md) | Active Response, Vulnerability Detection, CDB Lists, CIS Benchmark |
| [ClamAV + YARA](docs/clamav-yara.md) | Antivirus, malware analysis, regole YARA custom, stack di detection |
| [Troubleshooting](docs/troubleshooting.md) | Problemi riscontrati, soluzioni, comandi di manutenzione |

---

## Stato attuale del sistema

Il sistema è pienamente operativo:

- **Dashboard**: raggiungibile via HTTPS su IP locale porta 443
- **Ingestione log**: Filebeat attivo, indici `wazuh-alerts-*` popolati
- **Agenti**: configurabili su qualsiasi endpoint (Windows/Linux/macOS) puntando all'IP del Raspberry porta 1514
- **Regole custom**: attive per Cowrie (rule ID 100010-100013)
