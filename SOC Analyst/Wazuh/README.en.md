>  [Italiano](README.md) |  **English**

# Wazuh - SIEM & XDR on Raspberry Pi 5

Complete guide to installing Wazuh All-in-One (Manager + Indexer + Dashboard) on Raspberry Pi 5 with ARM64 architecture. This installation is **not** officially supported by Wazuh - I document here the manual process I followed, the errors encountered, and the solutions adopted.

---

## Theory: What is Wazuh

**Wazuh** is an open-source security platform that combines:

- **SIEM** (Security Information and Event Management): collects logs from multiple sources, normalizes them, correlates them, and generates alerts
- **XDR** (Extended Detection and Response): extends detection beyond traditional logs, including endpoint protection, vulnerability assessment, and compliance monitoring

### Architecture Components

| Component | Role | Underlying Technology | Required Resources |
|---|---|---|---|
| **Wazuh Manager** | Receives events from agents, analyzes them with rules and decoders, generates alerts | C, Python | Lightweight (~200MB RAM) |
| **Wazuh Indexer** | Indexes and stores alerts for search and visualization | OpenSearch (Elasticsearch fork) | Heavy (~1-2GB RAM) |
| **Wazuh Dashboard** | Web interface for viewing alerts, threat hunting, compliance | OpenSearch Dashboards (Kibana fork) | Moderate (~500MB RAM) |
| **Filebeat** | Transports alerts from the Manager to the Indexer | Elastic Filebeat | Lightweight (~100MB RAM) |
| **Wazuh Agent** | Installed on every endpoint to monitor, collects logs and sends them to the Manager | C | Minimal (~50MB RAM) |

### Data Flow

```
[Endpoint with Agent] --events (1514/TCP)--> [Wazuh Manager]
                                                |
                                    analysis with decoders + rules
                                                |
                                                v
                                        generates JSON alerts
                                                |
                                    [Filebeat] reads the alerts
                                                |
                                                v
                                        [Wazuh Indexer (OpenSearch)]
                                        indexes into wazuh-alerts-*
                                                |
                                                v
                                        [Wazuh Dashboard]
                                        visualizes and enables threat hunting
```

**Why Filebeat?** The Manager writes alerts as JSON files to disk. Filebeat acts as a "courier" - it reads these files, formats them, and sends them to the Indexer via HTTPS. Without Filebeat, the Dashboard would be empty because the Indexer would receive no data.

---

## The Challenge: Wazuh on ARM64

Wazuh is designed for **x86_64** architectures. On Raspberry Pi (aarch64/ARM64):

- The automatic installation script (`wazuh-install.sh`) **fails** with "Uncompatible system" - it does not recognize ARM64
- The official Docker containers are compiled for `amd64`, not `arm64` - they cause `exec format error` at startup
- Even forcing `platform: linux/amd64` in Docker Compose, the limited RAM and architectural differences prevent OpenSearch from starting

**Solution adopted:** Manual installation of ARM64 `.deb` packages from the Wazuh repository, forcing the architecture in the APT source list.

> **Note on resources:** The Raspberry Pi 5 with 8GB of RAM can handle it, but it is at its limit. With Wazuh All-in-One + Docker + Cowrie + Pi-hole all running simultaneously, RAM usage hovers around 6-7GB. 4GB would not be sufficient - the Indexer (OpenSearch) requires at least 1GB of Java heap.

---

## Documentation Index

| Document | Content |
|---|---|
| [Installation Guide](docs/installazione.en.md) | Steps 1-5: ARM64 repository, components, SSL certificates, dashboard, startup |
| [Deep Dive: TLS/PKI](docs/tls-pki.en.md) | TLS 1.2 handshake, mutual TLS, X.509 certificates, chain of trust |
| [Filebeat](docs/filebeat.en.md) | Installation, configuration, template, connection verification |
| [Deep Dive: ossec.conf](docs/ossec-conf.en.md) | Syscheck (FIM), rootcheck, localfile, JSON alert structure |
| [Suricata IDS/IPS](docs/suricata.en.md) | Network IDS, ET Open rules, Wazuh integration |
| [Rules Best Practices](docs/rules-best-practices.en.md) | Active Response, Vulnerability Detection, CDB Lists, CIS Benchmark |
| [ClamAV + YARA](docs/clamav-yara.en.md) | Antivirus, malware analysis, custom YARA rules, detection stack |
| [Troubleshooting](docs/troubleshooting.en.md) | Issues encountered, solutions, maintenance commands |

---

## Current System Status

The system is fully operational:

- **Dashboard**: reachable via HTTPS on local IP port 443
- **Log ingestion**: Filebeat active, `wazuh-alerts-*` indices populated
- **Agents**: configurable on any endpoint (Windows/Linux/macOS) pointing to the Raspberry Pi IP on port 1514
- **Custom rules**: active for Cowrie (rule ID 100010-100013)
