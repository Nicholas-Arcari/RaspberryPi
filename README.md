# Raspberry Pi 5 - Home Lab di Cyber Security & NAS

> Documentazione completa di un progetto reale per trasformare un Raspberry Pi 5 in un server multifunzione: NAS, SIEM, Honeypot, VPN, DNS Sinkhole e molto altro. Scritto da chi ci ha messo le mani, con errori, fix e lezioni imparate sul campo.

Questo repository raccoglie l'intera esperienza - dalla prima accensione al deployment finale - di un Raspberry Pi 5 configurato come infrastruttura di sicurezza domestica. Non e' una raccolta di comandi copiati da StackOverflow: ogni sezione documenta il **perche'** di ogni scelta, i problemi incontrati e le soluzioni adottate.

Il sistema operativo di base e' **OpenMediaVault 7** (Debian-based), scelto per la gestione NAS nativa. Tutti i servizi aggiuntivi (SIEM, VPN, Honeypot, DNS Blocker) girano in **container Docker**, garantendo isolamento, portabilita' e la possibilita' di distruggere e ricreare un servizio senza toccare il sistema host.

---

## Indice delle sezioni

| # | Sezione | Descrizione |
|---|---------|-------------|
| 1 | [First Setup](./First%20Setup/) | Installazione OS, boot da NVMe, configurazione iniziale SSH e bootloader |
| 2 | [NAS (Network Attached Storage)](./NAS%20(Network%20Attached%20Storage)/) | OpenMediaVault 7, filesystem, condivisioni SMB/NFS, Plex Media Server |
| 3 | [Docker & Portainer](./Docker%20%26%20Portainer/) | Installazione Docker su OMV, Portainer come management plane |
| 4 | [Secure your RaspberryPi](./Secure%20your%20RaspberryPi/) | Hardening SSH, Fail2ban, UFW, aggiornamenti automatici, Wazuh FIM |
| 5 | [VLAN (Virtual LAN)](./VLAN%20(Virtual%20LAN)/) | Segmentazione di rete con IPVLAN e VLAN tagging 802.1Q |
| 6 | [VPN (Virtual Private Network)](./VPN%20(Virtual%20Private%20Network)/) | WireGuard server con wg-easy, DDNS, gestione Double NAT/CGNAT |
| 7 | [ADS Blocker](./ADS%20Blocker/) | Pi-hole su Docker con rete MacVLAN, configurazione DNS e router |
| 8 | [Honeypot](./Honeypot/) | Cowrie SSH/Telnet honeypot con integrazione Wazuh SIEM |
| 9 | [SOC Analyst](./SOC%20Analyst/) | Ruolo e strumenti dell'analista SOC, con sotto-sezione Wazuh SIEM/XDR |
| 10 | [Security Assessment & Hardening](./Security%20Assessment%20%26%20Hardening/) | Red teaming del proprio lab: Nmap, Hydra, analisi rischi, firewall tuning |

---

## Architettura del progetto

```
Raspberry Pi 5 (8GB RAM) - Raspberry Pi OS Lite 64-bit (Bookworm)
│
├── Hardware & Boot
│   ├── Boot diretto da NVMe SSD (Patriot P320 256GB PCIe Gen 3x4)
│   ├── Bootloader EEPROM aggiornato all'ultima versione stable
│   ├── MicroSD mantenuta solo per recovery/emergenza
│   └── Alimentazione: alimentatore ufficiale 27W USB-C (5.1V / 5A)
│
├── Sistema Base: OpenMediaVault 7
│   ├── Gestione storage (NVMe, filesystem EXT4)
│   ├── Condivisioni di rete: SMB/CIFS + NFS
│   ├── Gestione utenti e permessi ACL
│   ├── Monitoraggio SMART dei dischi
│   └── Web UI su porta 80 (IP locale)
│
├── Container Platform: Docker + Portainer
│   ├── Docker Engine (docker.io da repo Debian, non CE)
│   ├── Docker Root Directory su NVMe (/var/lib/docker)
│   ├── Portainer CE su porta 9443 (HTTPS)
│   └── Reti Docker segmentate:
│       ├── bridge (default, per servizi interni)
│       ├── macvlan (Pi-hole - IP dedicato su LAN)
│       └── ipvlan_150 (VLAN 150 per isolamento avanzato)
│
├── Security Stack
│   ├── Wazuh SIEM All-in-One (Manager + Indexer + Dashboard)
│   │   ├── Intrusion Detection System (IDS)
│   │   ├── File Integrity Monitoring (FIM)
│   │   ├── Log collection e correlation
│   │   └── Dashboard HTTPS su porta 443
│   ├── Wazuh Agents
│   │   ├── Self-monitoring sul Raspberry Pi
│   │   ├── Agent su macchine Windows/Linux della rete
│   │   └── Comunicazione su porte 1514/1515 TCP
│   └── Regole custom per Cowrie (rule ID 100010-100013)
│
├── Network Protection
│   ├── WireGuard VPN (wg-easy, porta 51820 UDP)
│   │   ├── Accesso remoto alla LAN da qualsiasi rete
│   │   ├── DDNS tramite No-IP
│   │   └── Bypass CGNAT tramite DMZ sul provider FWA
│   ├── Pi-hole DNS Sinkhole
│   │   ├── Blocco pubblicita' e tracking a livello DNS
│   │   ├── IP dedicato 192.168.0.250 (MacVLAN)
│   │   └── 79.000+ domini in blocklist
│   └── UFW Firewall
│       ├── Default deny incoming
│       ├── Regole ordinate: Gateway first, then LAN block
│       └── Porte aperte solo per SSH, Dashboard, Wazuh agents
│
├── Threat Detection
│   ├── Cowrie Honeypot (SSH porta 2222, Telnet porta 2223)
│   │   ├── Emula un server SSH/Telnet vulnerabile
│   │   ├── Registra credenziali, comandi, sessioni
│   │   └── Log JSON ingestiti da Wazuh in tempo reale
│   └── Esposizione Internet
│       ├── Port forwarding per Honeypot (51820 VPN, 2222 SSH)
│       └── Ngrok tunnel come fallback per CGNAT
│
└── Network Segmentation (Target)
    ├── DMZ Network → Honeypot, VPN, servizi esposti
    ├── Internal Network → NAS, Pi-hole, servizi privati
    └── Management Network → Portainer, Wazuh Dashboard
```

---

## Topologia di rete

Vista d'insieme di tutti i componenti, IP, porte e flussi dati del lab:

```
                          INTERNET
                             │
                             │ IP pubblico (dinamico, DDNS: miodominio.ddns.net)
                             ▼
                    ┌──────────────────┐
                    │  Antenna FWA     │  Provider: Comeser
                    │  (CGNAT / DMZ)   │  NAT 1:1 verso router
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  Router TP-Link  │  192.168.0.1 (gateway)
                    │  Archer C50      │  DHCP, DDNS (No-IP), Port Forwarding
                    │                  │  Porte inoltrate:
                    │                  │    51820/UDP → Pi (WireGuard)
                    │                  │    2222/TCP  → Pi (Honeypot)
                    └────────┬─────────┘
                             │
                ─────────────┼────────────── LAN 192.168.0.0/24 ──────────
                             │
              ┌──────────────┴──────────────┐
              │     RASPBERRY PI 5 (8GB)    │
              │     192.168.0.102           │
              │     OS: RPi OS Lite 64-bit  │
              │     NVMe: Patriot P320      │
              │                             │
              │  ┌────────────────────────┐ │
              │  │ OpenMediaVault 7       │ │  :80  → Web UI NAS
              │  │ (sistema base)         │ │
              │  └────────────────────────┘ │
              │                             │
              │  ┌── DOCKER ENGINE ───────┐ │
              │  │                        │ │
              │  │  ┌──────────────────┐  │ │
              │  │  │ Portainer CE     │  │ │  :9443 → Web UI (HTTPS)
              │  │  │ (management)     │  │ │
              │  │  └──────────────────┘  │ │
              │  │                        │ │
              │  │  ┌──────────────────┐  │ │
              │  │  │ WireGuard/wg-easy│  │ │  :51820/UDP → tunnel VPN
              │  │  │ (VPN server)     │  │ │  :51821/TCP → Web UI
              │  │  │ Subnet: 10.8.0.0│  │ │
              │  │  └──────────────────┘  │ │
              │  │                        │ │
              │  │  ┌──────────────────┐  │ │
              │  │  │ Cowrie Honeypot  │  │ │  :2222/TCP → SSH finto
              │  │  │ (threat detect.) │  │ │  :2223/TCP → Telnet finto
              │  │  │ Log → Wazuh      │  │ │
              │  │  └──────────────────┘  │ │
              │  │                        │ │
              │  └────────────────────────┘ │
              │                             │
              │  ┌── WAZUH (bare metal) ──┐ │
              │  │ Manager    :1514/TCP   │ │  ← eventi dagli agent
              │  │            :1515/TCP   │ │  ← registrazione agent
              │  │ Indexer    :9200/TCP   │ │  ← API OpenSearch
              │  │ Dashboard  :443/TCP    │ │  ← Web UI (HTTPS)
              │  │ Filebeat   (interno)   │ │  Manager → Indexer
              │  └────────────────────────┘ │
              │                             │
              │  ┌── SICUREZZA HOST ──────┐ │
              │  │ UFW        (firewall)  │ │  default deny incoming
              │  │ Fail2ban   (anti-BF)   │ │  banna IP dopo 5 tentativi
              │  │ SSH        :22/TCP     │ │  solo chiave Ed25519, no root
              │  └────────────────────────┘ │
              └──────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │  Pi-hole (container Docker)  │
              │  192.168.0.250 (MacVLAN)     │  :53  → DNS sinkhole
              │  IP dedicato sulla LAN       │  :80  → Dashboard
              └─────────────────────────────┘
                             │
                ─────────────┼────────────── VLAN 150: 192.168.150.0/24 ──
                             │              (IPVLAN L2 su end0.150)
                             │              Segmentazione servizi esposti
                             │
              ┌──────────────┴──────────────┐
              │  DISPOSITIVI LAN             │
              │  ├─ PC Windows  192.168.0.50 │  Wazuh Agent installato
              │  ├─ Kali Linux  192.168.0.60 │  Wazuh Agent + pen testing
              │  ├─ Smartphone  (DHCP)       │  Client WireGuard VPN
              │  └─ Smart TV    (DHCP)       │  DNS → Pi-hole
              └─────────────────────────────┘
```

### Flussi dati principali

```
[1] ATTACCO ESTERNO (Internet → Honeypot → SIEM)
    Attaccante → Ngrok/Port Forward → :2222 → Cowrie → cowrie.json
    → Wazuh Agent (inotify) → Manager :1514 → Filebeat → Indexer → Dashboard

[2] BLOCCO DNS (Dispositivo LAN → Pi-hole)
    Smartphone → query DNS "ads.tracker.com" → Pi-hole :53
    → gravity.db lookup → BLOCKED (0.0.0.0) → nessuna pubblicita'

[3] VPN REMOTA (Smartphone fuori casa → LAN)
    Smartphone (4G) → miodominio.ddns.net:51820/UDP → Router
    → WireGuard → tunnel cifrato → LAN 192.168.0.0/24

[4] MONITORAGGIO (Host → SIEM)
    /var/log/auth.log, ufw.log, syslog → Wazuh Agent
    → Manager (decoder + rules) → alert JSON → Dashboard
```

---

## Requisiti hardware

| Componente | Dettaglio | Note |
|---|---|---|
| **Board** | Raspberry Pi 5 (8GB RAM) | I 4GB sono insufficienti per Wazuh Indexer + Dashboard |
| **Storage primario** | NVMe SSD M.2 2280 PCIe Gen 3x4 | Nel mio caso: Patriot P320 256GB |
| **Adattatore NVMe** | HAT/adattatore PCIe per RPi5 | Verificare compatibilita' e alimentazione |
| **Storage secondario** | MicroSD 16GB+ | Solo per recovery; il boot avviene da NVMe |
| **Alimentazione** | Alimentatore ufficiale RPi5 27W (5.1V/5A) | Con NVMe collegato, un alimentatore sottodimensionato causa instabilita' |
| **Rete** | Cavo Ethernet Cat5e/Cat6 | Wi-Fi sconsigliato per un server; MacVLAN richiede Ethernet |
| **Switch** | Switch gestito (managed) | Necessario solo per VLAN tagging 802.1Q |
| **Router** | Con supporto DDNS e Port Forwarding | Nel mio caso: TP-Link Archer C50 |

---

## Regola fondamentale del progetto

> **OpenMediaVault rimane il sistema operativo principale.** Nessun servizio aggiuntivo viene installato direttamente sull'host. Tutto gira in container Docker. Questo garantisce che un servizio malfunzionante non possa corrompere il NAS, e che ogni componente possa essere aggiornato, fermato o eliminato indipendentemente.

---

## Flusso di lettura consigliato

Per chi parte da zero, l'ordine consigliato e':

1. **First Setup** - Installare l'OS, configurare boot e NVMe
2. **NAS** - Configurare OpenMediaVault e le condivisioni
3. **Docker & Portainer** - Installare la piattaforma container
4. **Secure your RaspberryPi** - Hardening base prima di esporre servizi
5. **VPN** - Accesso remoto sicuro
6. **ADS Blocker** - Protezione DNS
7. **VLAN** - Segmentazione avanzata (opzionale, richiede switch gestito)
8. **Honeypot** - Deployment della trappola
9. **SOC Analyst / Wazuh** - SIEM per monitoraggio centralizzato
10. **Security Assessment** - Test e validazione dell'intero setup

---

## Stack tecnologico

| Layer | Tecnologia | Versione/Note |
|---|---|---|
| OS | Raspberry Pi OS Lite 64-bit | Bookworm (Debian 12). Trixie non supportata da OMV e Wazuh |
| NAS | OpenMediaVault 7 | Installato via script ufficiale OMV-extras |
| Container Runtime | Docker Engine (docker.io) | Da repository Debian, non Docker CE |
| Container Management | Portainer CE | Web UI su HTTPS:9443 |
| SIEM/XDR | Wazuh 4.9.x | All-in-One (Manager + Indexer + Dashboard) su ARM64 |
| Log Shipper | Filebeat | Trasporta alert dal Manager all'Indexer |
| VPN | WireGuard (wg-easy v13) | Container Docker, Web UI su porta 51821 |
| DNS Sinkhole | Pi-hole | Container Docker, rete MacVLAN |
| Honeypot | Cowrie | Container Docker, SSH porta 2222 |
| Firewall | UFW (Uncomplicated Firewall) | Frontend per iptables/nftables |
| Brute Force Protection | Fail2ban | Integrato con Wazuh per alerting |

---

## Quick Reference Card

Tabella di riferimento rapido per operazioni quotidiane e troubleshooting.

### Indirizzi e porte

| Servizio | IP | Porta | Protocollo | Accesso |
|---|---|---|---|---|
| Raspberry Pi (host) | `192.168.0.102` | 22/TCP | SSH | Solo LAN, chiave Ed25519 |
| OpenMediaVault | `192.168.0.102` | 80/TCP | HTTP | Solo LAN |
| Portainer | `192.168.0.102` | 9443/TCP | HTTPS | Solo LAN |
| Wazuh Dashboard | `192.168.0.102` | 443/TCP | HTTPS | Solo LAN |
| Wazuh Indexer API | `192.168.0.102` | 9200/TCP | HTTPS | Solo LAN |
| Wazuh Manager (eventi) | `192.168.0.102` | 1514/TCP | Wazuh protocol | Solo LAN (agent) |
| Wazuh Manager (registrazione) | `192.168.0.102` | 1515/TCP | Wazuh protocol | Solo LAN (agent) |
| Pi-hole | `192.168.0.250` | 53/UDP+TCP | DNS | Tutta la LAN |
| Pi-hole Dashboard | `192.168.0.250` | 80/TCP | HTTP | Solo LAN |
| WireGuard VPN | `192.168.0.102` | 51820/UDP | WireGuard | Internet (port forward) |
| WireGuard Web UI | `192.168.0.102` | 51821/TCP | HTTP | Solo LAN |
| Cowrie Honeypot | `192.168.0.102` | 2222/TCP | SSH (finto) | Internet (port forward) |
| Router gateway | `192.168.0.1` | 80/TCP | HTTP | Solo LAN |

### Credenziali default (da cambiare al primo accesso)

| Servizio | Username | Password | Note |
|---|---|---|---|
| SSH | `pi` | (chiave Ed25519) | Password disabilitata |
| OpenMediaVault | `admin` | `openmediavault` | Cambiare immediatamente |
| Portainer | (creato al primo accesso) | (creato al primo accesso) | Min 12 caratteri |
| Wazuh Dashboard | `admin` | `admin` | Cambiare con `wazuh-passwords-tool.sh` |
| WireGuard Web UI | - | (impostata nel docker-compose) | Variabile `PASSWORD` |
| Pi-hole Dashboard | - | (impostata nel docker-compose) | Variabile `WEBPASSWORD` |

### Comandi di emergenza

```bash
# === STATO DEI SERVIZI ===
sudo systemctl status docker wazuh-manager wazuh-indexer wazuh-dashboard
docker ps -a                        # Container attivi e fermi
sudo ufw status verbose             # Regole firewall attive
sudo fail2ban-client status sshd    # IP bannati

# === RIAVVIO SERVIZI ===
sudo systemctl restart docker       # Riavvia Docker (riavvia tutti i container)
sudo systemctl restart wazuh-manager wazuh-indexer wazuh-dashboard
docker restart portainer pihole wireguard cowrie   # Container singoli

# === LOG IN TEMPO REALE ===
docker logs -f cowrie --tail 50     # Log Cowrie (honeypot)
docker logs -f pihole --tail 50     # Log Pi-hole
sudo tail -f /var/log/auth.log      # Tentativi SSH
sudo tail -f /var/log/ufw.log       # Pacchetti bloccati/permessi dal firewall
sudo tail -f /var/ossec/logs/alerts/alerts.json   # Alert Wazuh in tempo reale

# === RECUPERO DA BLOCCO SSH ===
# Se ti sei chiuso fuori (regola UFW sbagliata o chiave SSH persa):
# 1. Collega monitor HDMI + tastiera USB al Pi
# 2. Login locale con username/password
# 3. sudo ufw disable                # Disabilita firewall temporaneamente
# 4. sudo ufw allow ssh              # Riapri SSH
# 5. sudo ufw enable                 # Riabilita
# Oppure: riflasha la MicroSD e usa il boot di recovery

# === PULIZIA SPAZIO DISCO ===
docker system df                    # Mostra spazio usato da Docker
docker system prune -a              # ATTENZIONE: rimuove tutto cio' che non e' in uso
sudo journalctl --vacuum-size=100M  # Limita i log di systemd a 100MB
```

---

## Checklist post-installazione

Dopo aver completato il setup di tutti i componenti, esegui questa verifica per confermare che tutto funzioni correttamente. Ogni check ha un comando e il risultato atteso.

### Infrastruttura base

```bash
# [ ] Sistema aggiornato
sudo apt update && apt list --upgradable
# Risultato atteso: nessun pacchetto da aggiornare (o solo pochi non-security)

# [ ] Boot da NVMe (se configurato)
lsblk | grep -E "nvme|mmcblk"
# Risultato atteso: la partizione root (/) e' su nvme0n1p2, non su mmcblk0

# [ ] EEPROM aggiornato
sudo rpi-eeprom-update
# Risultato atteso: "BOOTLOADER: up to date"
```

### Sicurezza

```bash
# [ ] SSH accetta solo chiavi pubbliche
ssh -o PasswordAuthentication=yes pi@localhost 2>&1 | grep -i "permission denied"
# Risultato atteso: "Permission denied" (password rifiutata)

# [ ] UFW attivo con policy corrette
sudo ufw status verbose | head -5
# Risultato atteso: "Status: active", "Default: deny (incoming), allow (outgoing)"

# [ ] Fail2ban attivo sulla jail SSH
sudo fail2ban-client status sshd
# Risultato atteso: "Filter" e "Actions" presenti, nessun errore

# [ ] Sysctl hardening applicato
sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space
# Risultato atteso: tcp_syncookies = 1, randomize_va_space = 2
```

### Container

```bash
# [ ] Docker attivo
docker version --format '{{.Server.Version}}'
# Risultato atteso: versione Docker (es. 20.10.x)

# [ ] Tutti i container in esecuzione
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# Risultato atteso: portainer, pihole, wireguard, cowrie tutti "Up"

# [ ] Portainer raggiungibile
curl -sk https://localhost:9443 | head -1
# Risultato atteso: HTML della pagina Portainer (non "connection refused")

# [ ] Pi-hole risponde alle query DNS
dig @192.168.0.250 google.com +short
# Risultato atteso: un indirizzo IP (es. 142.250.x.x)

# [ ] Pi-hole blocca i tracker
dig @192.168.0.250 ads.doubleclick.net +short
# Risultato atteso: 0.0.0.0 (bloccato)
```

### SIEM e Monitoraggio

```bash
# [ ] Wazuh Manager attivo
sudo systemctl is-active wazuh-manager
# Risultato atteso: "active"

# [ ] Wazuh Indexer attivo e raggiungibile
curl -sk https://localhost:9200 -u admin:admin | python3 -m json.tool | head -5
# Risultato atteso: JSON con nome del cluster e versione OpenSearch

# [ ] Wazuh Dashboard raggiungibile
curl -sk https://localhost:443 | head -1
# Risultato atteso: HTML della pagina di login

# [ ] Filebeat invia dati all'Indexer
sudo filebeat test output
# Risultato atteso: "elasticsearch: https://127.0.0.1:9200... OK"

# [ ] Agent locale connesso
sudo /var/ossec/bin/agent_control -l
# Risultato atteso: agent ID 000 o 001 con stato "Active"
```

### Honeypot

```bash
# [ ] Cowrie accetta connessioni
ssh -o StrictHostKeyChecking=no root@localhost -p 2222
# Risultato atteso: prompt di login (accetta password comuni come "12345")
# Digita "exit" per uscire

# [ ] I log Cowrie vengono generati
docker exec cowrie tail -1 /home/cowrie/cowrie-git/var/log/cowrie/cowrie.json
# Risultato atteso: riga JSON con l'ultimo evento
```

### VPN

```bash
# [ ] WireGuard in ascolto
ss -ulnp | grep 51820
# Risultato atteso: riga con 0.0.0.0:51820 (LISTEN)

# [ ] Web UI raggiungibile
curl -s http://localhost:51821 | head -1
# Risultato atteso: HTML della pagina wg-easy

# [ ] Tunnel funzionante (da un client connesso)
# Sul client VPN: ping 192.168.0.102
# Risultato atteso: risposta dal Pi
```

### VLAN (se configurata)

```bash
# [ ] Interfaccia VLAN attiva
ip link show end0.150
# Risultato atteso: stato UP

# [ ] Rete Docker IPVLAN presente
docker network inspect ipvlan_150 --format '{{.IPAM.Config}}'
# Risultato atteso: [{192.168.150.0/24 192.168.150.1 map[]}]
```

> **Frequenza consigliata:** Esegui questa checklist dopo ogni modifica significativa (aggiornamento OS, aggiunta container, modifica regole UFW) e come minimo una volta al mese. Puoi automatizzarla con lo script `scripts/setup.sh verify`.

---

## Script di automazione

Lo script [`scripts/setup.sh`](./scripts/setup.sh) riproduce l'intero lab da zero. Ogni comando e' commentato con la spiegazione di cosa fa e perche'. Supporta l'esecuzione modulare:

```bash
# Setup completo (tutti i moduli in ordine)
sudo ./scripts/setup.sh all

# Singolo modulo
sudo ./scripts/setup.sh hardening
sudo ./scripts/setup.sh docker
sudo ./scripts/setup.sh pihole

# Verifica stato di tutti i servizi
sudo ./scripts/setup.sh verify
```

> **Nota su Wazuh:** Il modulo `wazuh` non automatizza l'installazione (ARM64 non supportato ufficialmente, ogni passo richiede verifica manuale). Fornisce le istruzioni passo-passo da seguire.

---

## Nota sulla sicurezza

Questo progetto espone deliberatamente un honeypot su Internet. Le configurazioni documentate includono misure di isolamento (firewall, segmentazione di rete, container sandbox), ma **un sistema esposto a Internet richiede manutenzione costante**: aggiornamenti, monitoraggio dei log, revisione delle regole firewall.

Non replicare questa configurazione senza comprendere i rischi. Un honeypot mal configurato e' una porta aperta sulla tua rete domestica.

---

## Licenza

Questo repository e' pubblico a scopo educativo. I comandi e le configurazioni documentati sono specifici per il mio ambiente di rete e potrebbero richiedere adattamenti per funzionare correttamente nel vostro.
