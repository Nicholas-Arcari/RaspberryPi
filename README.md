# Raspberry Pi Server – NAS, VPN, Ad-Blocker, Honeypot, ecc...

Questo repository documenta i setup da applicare su di un Raspberry Pi utilizzato come server multifunzione, basato su **OpenMediaVault (OMV)** come sistema NAS e **Docker** per l’esecuzione di servizi aggiuntivi come VPN, ad-blocker, honeypot, e molti altri giochini simpatici.

La guida è pensata per essere riproducibile passo-passo, anche da chi parte da zero.

---

## Architettura del progetto
```bash
Raspberry Pi 5 (8GB RAM)
│
│ ## Hardware & Boot ##
├── Boot & OS
│   ├── Bootloader EEPROM aggiornato
│   ├── Boot da NVMe (no MicroSD)
│   └── Raspberry Pi OS Lite 64-bit (Bookworm)
│
├── Storage
│   ├── NVMe SSD
│   │   ├── / (root filesystem)
│   │   ├── /var/lib/docker
│   │   ├── /var/log
│   │   └── PCAP / Log SIEM
│   └── MicroSD (solo recovery / emergenza)
│
│ ## NAS & Storage Management ##
├── OpenMediaVault (OMV 7)
│   ├── Storage Management
│   │   ├── Filesystem NVMe (EXT4)
│   │   ├── Shared Folders
│   │   └── ACL & Permissions
│   │
│   ├── Services
│   │   ├── SMB/CIFS (Windows)
│   │   ├── NFS (Linux)
│   │   └── FTP/SFTP (opzionale)
│   │
│   └── Event Monitoring
│       ├── SMART monitoring
│       ├── Disk health alerts
│       └── Log forwarding → Wazuh
│
│ ## Container Platform ##
├── Container Platform
│   ├── Docker Engine
│   │   ├── Docker Root Dir → NVMe
│   │   └── Logging driver configurato
│   │
│   ├── Portainer (Management Plane)
│   │   ├── Stack management
│   │   └── Role-based access
│   │
│   └── Docker Networks
│       ├── dmz_net
│       ├── internal_net
│       └── management_net
│
│ ## Network Segmentation (Docker) ##
├── DMZ Network
│   ├── Reverse Proxy (Nginx / Traefik)
│   ├── VPN (WireGuard / OpenVPN)
│   └── Honeypots
│       ├── Cowrie (SSH/Telnet)
│       ├── Dionaea (Malware)
│       └── (opz.) T-Pot stack
│
├── Internal Network
│   ├── OpenMediaVault services
│   ├── Pi-hole / AdGuard Home
│   └── Internal-only containers
│
├── Management Network
│   ├── Portainer
│   ├── Wazuh Dashboard
│   └── Monitoring tools
│
│ ## Security & Monitoring ##
├── Wazuh SIEM (All-in-One)
│   ├── Wazuh Manager
│   ├── Wazuh Indexer (OpenSearch)
│   └── Wazuh Dashboard
│
├── Wazuh Agents
│   ├── Agent on Raspberry Pi (self-monitoring)
│   ├── Agent on OMV services
│   └── Agent on Windows / macOS PC
│
├── Integrations
│   ├── VirusTotal API
│   │   └── File hash scan on NAS uploads
│   ├── Docker logs ingestion
│   └── Syslog / Auth logs
│
└── Network Forensics
    ├── Arkime (Full Packet Capture)
    │   ├── PCAP storage → NVMe
    │   └── Session analysis
    │
    └── Honeypot Telemetry
        ├── Attack source IPs
        ├── Payload analysis
        └── Correlation with Wazuh alerts
```

Riassunto TREE compatto:

```bash
Raspberry Pi 5 (8GB)
│
├── Boot & Storage (NVMe-first architecture)
│
├── OpenMediaVault 7
│   └── NAS services & disk monitoring
│
├── Docker Platform
│   ├── Portainer
│   ├── Segmented Networks (DMZ / Internal / Management)
│   └── Persistent volumes on NVMe
│
├── Security Stack
│   ├── Wazuh SIEM (All-in-One)
│   ├── Agents (Pi, OMV, Client PCs)
│   └── VirusTotal integration
│
├── Network Protection
│   ├── VPN (WireGuard)
│   ├── Pi-hole / AdGuard
│   └── Reverse Proxy
│
└── Threat Detection
    ├── Honeypots (Cowrie, Dionaea, T-Pot)
    └── Network Forensics (Arkime)
```


**Regola fondamentale:**  
OpenMediaVault rimane il sistema principale.  
Tutti i servizi aggiuntivi devono essere eseguiti tramite Docker per evitare conflitti.

---

## Requisiti hardware

- Raspberry Pi 5
- MicroSD (minimo 16 GB) con Raspberry Pi OS Lite
- NVMe SSD con adattatore compatibile USB-C / PCIe (Patriot P320 256GB SSD interno - NVMe PCle Gen 3x4 - M.2 2280)
- Alimentazione adeguata per Pi e NVMe
- Accesso via SSH da PC o terminale locale
- Cavo di rete (Ethernet) consigliato per stabilità