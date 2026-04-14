>  [English](installazione-pihole.en.md) |  **Italiano**

# Installazione Pi-hole con Docker e MacVLAN

## Il Problema: Conflitto della Porta 80

OpenMediaVault (il nostro NAS) occupa la porta 80 per la sua interfaccia web. Anche Pi-hole richiede la porta 80 per la dashboard. Inoltre, Pi-hole necessita della porta 53 (DNS), spesso occupata da `systemd-resolved`.

### Cosa NON fare

**Non installare Pi-hole direttamente sull'host** con il comando che si trova ovunque online:

```bash
# ⚠️ NON ESEGUIRE QUESTO COMANDO ⚠️
curl -sSL https://install.pi-hole.net | bash
```

Questo installa Pi-hole "bare metal" (direttamente sul sistema operativo), causando:

- Conflitto sulla porta 80 con OMV (nginx)
- Conflitto sulla porta 53 con `systemd-resolved`
- Installazione di una seconda istanza di `lighttpd` che interferisce con nginx di OMV
- Doppia gestione DNS che crea confusione

Se per errore l'avessi fatto, ecco cosa vedresti - queste sono schermate dell'installer bare metal che **non** va usato nel nostro setup:

![Installer bare metal di Pi-hole - selezione DNS upstream. Questa modalità di installazione NON va usata con Docker](../img/pihole-baremetal-dns-warning.jpg)

![Installer bare metal completato - NON applicabile al nostro setup Docker](../img/pihole-baremetal-install-warning.jpg)

### La soluzione: Docker + MacVLAN

Invece di combattere per le porte, diamo a Pi-hole un **indirizzo IP dedicato** sulla rete locale usando il driver MacVLAN. Il container Pi-hole appare come un dispositivo fisico separato con tutte le porte libere:

- Raspberry Pi (host/NAS): `192.168.0.102` → porta 80 = OMV
- Pi-hole (container): `192.168.0.250` → porta 80 = dashboard Pi-hole, porta 53 = DNS

Nessun conflitto, nessun port mapping.

---

## Configurazione di rete

| Componente | IP | Ruolo |
|---|---|---|
| Router (Gateway) | `192.168.0.1` | DHCP, routing, NAT |
| Raspberry Pi (Host) | `192.168.0.102` | NAS (OMV), Docker host |
| Pi-hole (Container) | `192.168.0.250` | DNS sinkhole |
| Subnet | `192.168.0.0/24` | Rete locale |
| Interfaccia fisica RPi5 | `end0` | Ethernet (su RPi5 Bookworm è `end0`, non `eth0`) |

> **L'IP 192.168.0.250 deve essere fuori dal range DHCP del router.** Se il router assegna IP da `.100` a `.200`, il `.250` è sicuro. Altrimenti, rischi che il router assegni lo stesso IP a un altro dispositivo, causando conflitti ARP.

---

## Installazione Passo-Passo

### 1. Struttura directory

```bash
mkdir -p ~/pihole
cd ~/pihole
```

### 2. Docker Compose

Creare il file `docker-compose.yml`:

```yaml
version: "3"

services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    hostname: pihole-nas
    domainname: lan
    networks:
      pihole_net:
        ipv4_address: 192.168.0.250
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
    environment:
      TZ: 'Europe/Rome'
      FTLCONF_LOCAL_IPV4: 192.168.0.250
      # La password la impostiamo dopo da CLI per non lasciarla in chiaro nel file
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    restart: unless-stopped

networks:
  pihole_net:
    driver: macvlan
    driver_opts:
      parent: end0  # Verificare con 'ip link' - su RPi5 Bookworm è end0, su RPi4 è eth0
    ipam:
      config:
        - subnet: 192.168.0.0/24
          gateway: 192.168.0.1
          ip_range: 192.168.0.248/29  # Range .248-.255 riservato a Docker MacVLAN
```

**Spiegazione dei parametri di rete MacVLAN:**

- `parent: end0`: l'interfaccia fisica su cui Docker crea l'interfaccia virtuale MacVLAN
- `ip_range: 192.168.0.248/29`: un piccolo range di 8 IP (`.248` a `.255`) riservato ai container MacVLAN. Questo evita che Docker assegni IP in conflitto con il DHCP del router
- `cap_add: NET_ADMIN`: necessario perchè Pi-hole deve poter modificare la configurazione di rete (binding su porta 53, DHCP se abilitato)

### 3. Avvio e configurazione password

```bash
# Avvio in background
docker compose up -d

# Imposta la password della dashboard
docker exec -it pihole pihole setpassword tua_password_sicura
```

![Dashboard Pi-hole appena avviata - 79.811 domini in blocklist, 0 query (appena installato)](../img/pihole-dashboard.jpg)
