>  [English](README.en.md) |  **Italiano**

# Raspberry Pi 5 - Home Lab di Cyber Security & NAS

> Documentazione completa di un progetto reale per trasformare un Raspberry Pi 5 in un server multifunzione: NAS, SIEM, Honeypot, VPN, DNS Sinkhole e molto altro. Scritto da chi ci ha messo le mani, con errori, fix e lezioni imparate sul campo.

Questo repository raccoglie l'intera esperienza - dalla prima accensione al deployment finale - di un Raspberry Pi 5 configurato come infrastruttura di sicurezza domestica. Non è una raccolta di comandi copiati da StackOverflow: ogni sezione documenta il **perche'** di ogni scelta, i problemi incontrati e le soluzioni adottate.

Il sistema operativo di base è **OpenMediaVault 7** (Debian-based), scelto per la gestione NAS nativa. Tutti i servizi aggiuntivi (SIEM, VPN, Honeypot, DNS Blocker) girano in **container Docker**, garantendo isolamento, portabilità e la possibilità di distruggere e ricreare un servizio senza toccare il sistema host.

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
| 11 | [Incident Recovery & Resilience](./Incident%20Recovery%20%26%20Resilience/) | Runbook operativi: triage, accesso perso, recovery DNS/Wazuh/VPN, verifica difese, integrita' post-downtime, LAN health check, backup e disaster recovery |

### Risorse trasversali

| Documento | Contenuto |
|---|---|
| [Topologia di rete](docs/topologia-rete.md) | Diagramma ASCII completo di tutti i componenti, IP, porte e flussi dati |
| [Quick Reference Card](docs/quick-reference.md) | Indirizzi, porte, credenziali default, comandi di emergenza |
| [Checklist post-installazione](docs/checklist-post-installazione.md) | 20+ verifiche con comandi e risultati attesi per ogni componente |

---

## Architettura del progetto

```
Raspberry Pi 5 (8GB RAM) - Raspberry Pi OS Lite 64-bit (Bookworm)
|
|-- Hardware & Boot
|   |-- Boot diretto da NVMe SSD (Patriot P320 256GB PCIe Gen 3x4)
|   |-- Bootloader EEPROM aggiornato all'ultima versione stable
|   |-- MicroSD mantenuta solo per recovery/emergenza
|   +-- Alimentazione: alimentatore ufficiale 27W USB-C (5.1V / 5A)
|
|-- Sistema Base: OpenMediaVault 7
|   |-- Gestione storage (NVMe, filesystem EXT4)
|   |-- Condivisioni di rete: SMB/CIFS + NFS
|   |-- Gestione utenti e permessi ACL
|   |-- Monitoraggio SMART dei dischi
|   +-- Web UI su porta 80 (IP locale)
|
|-- Container Platform: Docker + Portainer
|   |-- Docker Engine (docker.io da repo Debian, non CE)
|   |-- Docker Root Directory su NVMe (/var/lib/docker)
|   |-- Portainer CE su porta 9443 (HTTPS)
|   +-- Reti Docker segmentate:
|       |-- bridge (default, per servizi interni)
|       |-- macvlan (Pi-hole - IP dedicato su LAN)
|       +-- ipvlan_150 (VLAN 150 per isolamento avanzato)
|
|-- Security Stack
|   |-- Wazuh SIEM All-in-One (Manager + Indexer + Dashboard)
|   |-- Wazuh Agents (self-monitoring + host Windows/Linux)
|   +-- Regole custom per Cowrie (rule ID 100010-100013)
|
|-- Network Protection
|   |-- WireGuard VPN (wg-easy, porta 51820 UDP)
|   |-- Pi-hole DNS Sinkhole (79.000+ domini bloccati)
|   +-- UFW Firewall (default deny incoming)
|
|-- Threat Detection
|   |-- Cowrie Honeypot (SSH porta 2222, Telnet porta 2223)
|   +-- Esposizione Internet (port forward + Ngrok fallback)
|
+-- Network Segmentation
    |-- DMZ Network -> servizi esposti
    |-- Internal Network -> servizi privati
    +-- Management Network -> Portainer, Wazuh Dashboard
```

---

## Requisiti hardware

| Componente | Dettaglio | Note |
|---|---|---|
| **Board** | Raspberry Pi 5 (8GB RAM) | I 4GB sono insufficienti per Wazuh Indexer + Dashboard |
| **Storage primario** | NVMe SSD M.2 2280 PCIe Gen 3x4 | Nel mio caso: Patriot P320 256GB |
| **Adattatore NVMe** | HAT/adattatore PCIe per RPi5 | Verificare compatibilità e alimentazione |
| **Storage secondario** | MicroSD 16GB+ | Solo per recovery; il boot avviene da NVMe |
| **Alimentazione** | Alimentatore ufficiale RPi5 27W (5.1V/5A) | Con NVMe collegato, un alimentatore sottodimensionato causa instabilità |
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

Una volta costruito e validato il lab, la sezione **[Incident Recovery & Resilience](./Incident%20Recovery%20%26%20Resilience/)** e' il riferimento operativo per gestirlo nel tempo: cosa fare quando qualcosa si rompe, come verificare che le difese funzionino ancora e come recuperare da un disastro. E' la differenza tra un progetto da vetrina e un sistema che qualcuno gestisce davvero.

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

## Script di automazione

Lo script [`scripts/setup.sh`](./scripts/setup.sh) riproduce l'intero lab da zero. Ogni comando è commentato con la spiegazione di cosa fa e perche'. Supporta l'esecuzione modulare:

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

Non replicare questa configurazione senza comprendere i rischi. Un honeypot mal configurato è una porta aperta sulla tua rete domestica.

---

## Licenza

Questo repository è pubblico a scopo educativo. I comandi e le configurazioni documentati sono specifici per il mio ambiente di rete e potrebbero richiedere adattamenti per funzionare correttamente nel vostro.
