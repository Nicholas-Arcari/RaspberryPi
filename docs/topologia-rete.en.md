>  [Italiano](topologia-rete.md) |  **English**

# Network Topology

Overview of all components, IPs, ports and data flows in the lab:

```
                          INTERNET
                             |
                             | Public IP (dynamic, DDNS: mydomain.ddns.net)
                             v
                    +------------------+
                    |  FWA Antenna     |  Provider: Comeser
                    |  (CGNAT / DMZ)   |  1:1 NAT to router
                    +--------+---------+
                             |
                             v
                    +------------------+
                    |  Router TP-Link  |  192.168.0.1 (gateway)
                    |  Archer C50      |  DHCP, DDNS (No-IP), Port Forwarding
                    |                  |  Forwarded ports:
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
              |  | OpenMediaVault 7       | |  :80  -> NAS Web UI
              |  | (base system)          | |
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
              |  |  | WireGuard/wg-easy|  | |  :51820/UDP -> VPN tunnel
              |  |  | (VPN server)     |  | |  :51821/TCP -> Web UI
              |  |  | Subnet: 10.8.0.0|  | |
              |  |  +------------------+  | |
              |  |                        | |
              |  |  +------------------+  | |
              |  |  | Cowrie Honeypot  |  | |  :2222/TCP -> Fake SSH
              |  |  | (threat detect.) |  | |  :2223/TCP -> Fake Telnet
              |  |  | Logs -> Wazuh    |  | |
              |  |  +------------------+  | |
              |  |                        | |
              |  +------------------------+ |
              |                             |
              |  +-- WAZUH (bare metal) --+ |
              |  | Manager    :1514/TCP   | |  <-- events from agents
              |  |            :1515/TCP   | |  <-- agent registration
              |  | Indexer    :9200/TCP   | |  <-- OpenSearch API
              |  | Dashboard  :443/TCP    | |  <-- Web UI (HTTPS)
              |  | Filebeat   (internal)  | |  Manager -> Indexer
              |  +------------------------+ |
              |                             |
              |  +-- HOST SECURITY -------+ |
              |  | UFW        (firewall)  | |  default deny incoming
              |  | Fail2ban   (anti-BF)   | |  bans IP after 5 attempts
              |  | SSH        :22/TCP     | |  Ed25519 key only, no root
              |  +------------------------+ |
              +-----------------------------+
                             |
              +--------------+--------------+
              |  Pi-hole (Docker container)  |
              |  192.168.0.250 (MacVLAN)     |  :53  -> DNS sinkhole
              |  Dedicated IP on LAN         |  :80  -> Dashboard
              +-----------------------------+
                             |
                -------------+-------------- VLAN 150: 192.168.150.0/24 --
                             |              (IPVLAN L2 on end0.150)
                             |              Exposed services segmentation
                             |
              +--------------+--------------+
              |  LAN DEVICES                |
              |  |-- Windows PC  192.168.0.50|  Wazuh Agent installed
              |  |-- Kali Linux  192.168.0.60|  Wazuh Agent + pen testing
              |  |-- Smartphone  (DHCP)      |  WireGuard VPN client
              |  +-- Smart TV    (DHCP)      |  DNS -> Pi-hole
              +-----------------------------+
```

---

## Main Data Flows

```
[1] EXTERNAL ATTACK (Internet -> Honeypot -> SIEM)
    Attacker -> Ngrok/Port Forward -> :2222 -> Cowrie -> cowrie.json
    -> Wazuh Agent (inotify) -> Manager :1514 -> Filebeat -> Indexer -> Dashboard

[2] DNS BLOCKING (LAN Device -> Pi-hole)
    Smartphone -> DNS query "ads.tracker.com" -> Pi-hole :53
    -> gravity.db lookup -> BLOCKED (0.0.0.0) -> no ads

[3] REMOTE VPN (Smartphone outside home -> LAN)
    Smartphone (4G) -> mydomain.ddns.net:51820/UDP -> Router
    -> WireGuard -> encrypted tunnel -> LAN 192.168.0.0/24

[4] MONITORING (Host -> SIEM)
    /var/log/auth.log, ufw.log, syslog -> Wazuh Agent
    -> Manager (decoder + rules) -> JSON alert -> Dashboard
```
