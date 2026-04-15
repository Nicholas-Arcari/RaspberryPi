>  [English](topologia-rete.en.md) |  **Italiano**

# Topologia di rete

Vista d'insieme di tutti i componenti, IP, porte e flussi dati del lab:

```
                          INTERNET
                             |
                             | IP pubblico (dinamico, DDNS: miodominio.ddns.net)
                             v
                    +------------------+
                    |  Antenna FWA     |  Provider: Comeser
                    |  (CGNAT / DMZ)   |  NAT 1:1 verso router
                    +--------+---------+
                             |
                             v
                    +------------------+
                    |  Router TP-Link  |  192.168.0.1 (gateway)
                    |  Archer C50      |  DHCP, DDNS (No-IP), Port Forwarding
                    |                  |  Porte inoltrate:
                    |                  |    51820/UDP -> Pi (WireGuard)
                    |                  |    2222/TCP  -> Pi (Honeypot)
                    +--------+---------+
                             |
                -------------+-------------- LAN 192.168.0.0/24 ------
                             |
              +--------------+--------------+
              |     RASPBERRY PI 5 (8GB)    |
              |     192.168.0.102           |
              |     OS: RPi OS Lite 64-bit  |
              |     NVMe: Patriot P320      |
              |                             |
              |  +------------------------+ |
              |  | OpenMediaVault 7       | |  :80  -> Web UI NAS
              |  | (sistema base)         | |
              |  +------------------------+ |
              |                             |
              |  +-- DOCKER ENGINE -------+ |
              |  |                        | |
              |  |  +------------------+  | |
              |  |  | Portainer CE     |  | |  :9443 -> Web UI (HTTPS)
              |  |  | (management)     |  | |
              |  |  +------------------+  | |
              |  |                        | |
              |  |  +------------------+  | |
              |  |  | WireGuard/wg-easy|  | |  :51820/UDP -> tunnel VPN
              |  |  | (VPN server)     |  | |  :51821/TCP -> Web UI
              |  |  | Subnet: 10.8.0.0|  | |
              |  |  +------------------+  | |
              |  |                        | |
              |  |  +------------------+  | |
              |  |  | Cowrie Honeypot  |  | |  :2222/TCP -> SSH finto
              |  |  | (threat detect.) |  | |  :2223/TCP -> Telnet finto
              |  |  | Log -> Wazuh     |  | |
              |  |  +------------------+  | |
              |  |                        | |
              |  +------------------------+ |
              |                             |
              |  +-- WAZUH (bare metal) --+ |
              |  | Manager    :1514/TCP   | |  <-- eventi dagli agent
              |  |            :1515/TCP   | |  <-- registrazione agent
              |  | Indexer    :9200/TCP   | |  <-- API OpenSearch
              |  | Dashboard  :443/TCP    | |  <-- Web UI (HTTPS)
              |  | Filebeat   (interno)   | |  Manager -> Indexer
              |  +------------------------+ |
              |                             |
              |  +-- SICUREZZA HOST ------+ |
              |  | UFW        (firewall)  | |  default deny incoming
              |  | Fail2ban   (anti-BF)   | |  banna IP dopo 5 tentativi
              |  | SSH        :22/TCP     | |  solo chiave Ed25519, no root
              |  +------------------------+ |
              +-----------------------------+
                             |
              +--------------+--------------+
              |  Pi-hole (container Docker)  |
              |  192.168.0.250 (MacVLAN)     |  :53  -> DNS sinkhole
              |  IP dedicato sulla LAN       |  :80  -> Dashboard
              +-----------------------------+
                             |
                -------------+-------------- VLAN 150: 192.168.150.0/24 --
                             |              (IPVLAN L2 su end0.150)
                             |              Segmentazione servizi esposti
                             |
              +--------------+--------------+
              |  DISPOSITIVI LAN             |
              |  |-- PC Windows  192.168.0.50|  Wazuh Agent installato
              |  |-- Kali Linux  192.168.0.60|  Wazuh Agent + pen testing
              |  |-- Smartphone  (DHCP)      |  Client WireGuard VPN
              |  +-- Smart TV    (DHCP)      |  DNS -> Pi-hole
              +-----------------------------+
```

---

## Flussi dati principali

```
[1] ATTACCO ESTERNO (Internet -> Honeypot -> SIEM)
    Attaccante -> Ngrok/Port Forward -> :2222 -> Cowrie -> cowrie.json
    -> Wazuh Agent (inotify) -> Manager :1514 -> Filebeat -> Indexer -> Dashboard

[2] BLOCCO DNS (Dispositivo LAN -> Pi-hole)
    Smartphone -> query DNS "ads.tracker.com" -> Pi-hole :53
    -> gravity.db lookup -> BLOCKED (0.0.0.0) -> nessuna pubblicità

[3] VPN REMOTA (Smartphone fuori casa -> LAN)
    Smartphone (4G) -> miodominio.ddns.net:51820/UDP -> Router
    -> WireGuard -> tunnel cifrato -> LAN 192.168.0.0/24

[4] MONITORAGGIO (Host -> SIEM)
    /var/log/auth.log, ufw.log, syslog -> Wazuh Agent
    -> Manager (decoder + rules) -> alert JSON -> Dashboard
```
