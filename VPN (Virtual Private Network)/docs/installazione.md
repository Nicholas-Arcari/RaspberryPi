# Installazione di WireGuard con Docker

## Creazione della directory

```bash
mkdir -p ~/wireguard
cd ~/wireguard
```

## Docker Compose

Creare il file `docker-compose.yml`:

```yaml
version: "3.8"
services:
  wg-easy:
    environment:
      # Il dominio DDNS che punta al tuo IP pubblico
      - WG_HOST=miodominio.ddns.net

      # Password per la Web UI di gestione
      - PASSWORD=LaMiaPasswordSegreta

      # Porta del tunnel VPN (deve corrispondere al port forwarding)
      - WG_PORT=51820

      # Subnet interna della VPN - ogni client riceve un IP 10.8.0.x
      - WG_DEFAULT_ADDRESS=10.8.0.x

      # DNS usato dai client VPN
      # 8.8.8.8 = Google DNS. Se hai Pi-hole, metti il suo IP
      - WG_DEFAULT_DNS=8.8.8.8

      # Subnet raggiungibili tramite VPN:
      # - 192.168.0.0/24 = rete locale di casa
      # - 10.8.0.0/24 = rete VPN (per comunicazione tra client VPN)
      # - 0.0.0.0/0 = tutto il traffico (full tunnel)
      - WG_ALLOWED_IPS=192.168.0.0/24, 10.8.0.0/24, 0.0.0.0/0

      # MTU ridotto per compatibilita' con reti mobili
      - WG_MTU=1280

    # IMPORTANTE: versione 13 - vedi troubleshooting
    image: ghcr.io/wg-easy/wg-easy:13
    container_name: wireguard
    volumes:
      - .:/etc/wireguard
    ports:
      - "51820:51820/udp"  # Tunnel VPN
      - "51821:51821/tcp"  # Web UI di gestione
    restart: unless-stopped
    cap_add:
      - NET_ADMIN     # Necessario per creare interfacce di rete
      - SYS_MODULE    # Necessario per caricare il modulo kernel WireGuard
    sysctls:
      - net.ipv4.ip_forward=1           # Abilita il routing tra interfacce
      - net.ipv4.conf.all.src_valid_mark=1  # Necessario per il masquerading
```

## Spiegazione dei parametri chiave

**`WG_ALLOWED_IPS`** - Controlla quali destinazioni sono raggiungibili tramite il tunnel VPN:

- `192.168.0.0/24`: solo traffico verso la LAN di casa passa per la VPN (split tunnel)
- `0.0.0.0/0`: TUTTO il traffico passa per la VPN, incluso il browsing web (full tunnel)
- La combinazione che uso include entrambi, dando al client pieno accesso sia alla LAN che a Internet tramite il tunnel

**`WG_MTU=1280`** - Il MTU (Maximum Transmission Unit) e' la dimensione massima di un pacchetto di rete. Il valore standard e' 1500 byte. WireGuard aggiunge un header di ~60-80 byte a ogni pacchetto (encapsulation), quindi il MTU effettivo deve essere ridotto. Con 1280:

```
[IP header: 20B] [UDP header: 8B] [WG header: ~32B] [Payload: 1280B] = ~1340B < 1500B
```

Su reti mobili 4G/5G, il MTU del provider puo' essere gia' ridotto (1400-1420). Se il pacchetto WireGuard supera il MTU del provider, viene frammentato, causando rallentamenti o timeout. 1280 e' il minimo garantito da IPv6 e funziona ovunque.

## Le regole iptables di wg-easy (PostUp/PostDown)

Quando il container WireGuard si avvia, wg-easy esegue automaticamente regole iptables equivalenti a queste (configurabili con `WG_POST_UP` e `WG_POST_DOWN`):

```bash
# PostUp - eseguite all'avvio dell'interfaccia wg0:
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# PostDown - eseguite allo stop:
iptables -D FORWARD -i wg0 -j ACCEPT
iptables -D FORWARD -o wg0 -j ACCEPT
iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```

**Analisi delle regole:**

| Regola | Chain | Significato |
|---|---|---|
| `FORWARD -i wg0 -j ACCEPT` | FORWARD | Accetta pacchetti **provenienti** dal tunnel VPN e diretti verso la LAN o Internet. Senza questa regola, il kernel scarterebbe il traffico dei client VPN |
| `FORWARD -o wg0 -j ACCEPT` | FORWARD | Accetta pacchetti **diretti** verso il tunnel VPN (risposte dalla LAN/Internet verso i client VPN) |
| `POSTROUTING -o eth0 -j MASQUERADE` | NAT | **Critico**: esegue Source NAT (SNAT) sui pacchetti in uscita dall'interfaccia fisica. Quando un client VPN (10.8.0.2) accede a un dispositivo sulla LAN (192.168.0.50), l'IP sorgente viene riscritto con l'IP del Raspberry Pi (192.168.0.102). Senza questa regola, il dispositivo di destinazione riceverebbe un pacchetto con sorgente 10.8.0.2 e non saprebbe come rispondere (non ha una rotta verso la subnet 10.8.0.0/24) |

**`MASQUERADE` vs `SNAT`:** Su un'interfaccia con IP dinamico (come nel nostro caso con DHCP), si usa `MASQUERADE` che determina l'IP sorgente automaticamente ad ogni pacchetto. Su un'interfaccia con IP statico, `SNAT --to-source <IP>` sarebbe leggermente piu' efficiente perche' non deve fare il lookup dell'IP ad ogni pacchetto.

Il `sysctl` `net.ipv4.ip_forward=1` nel Docker Compose abilita il routing tra interfacce nel namespace del container - senza, il kernel scarterebbe qualsiasi pacchetto non destinato a se' stesso.

## Avvio

```bash
docker compose up -d
```

Web UI raggiungibile su: `http://192.168.0.102:51821`

## Verifica dello stato del tunnel: `wg show`

Dopo aver connesso un client, entrare nel container per verificare lo stato:

```bash
docker exec -it wireguard wg show
```

Output esempio con due client connessi:

```
interface: wg0
  public key: sRvY7mZB3K+x4QJn0dR1zE8bGPaj5N9vqKsMwoXf+Ew=
  private key: (hidden)
  listening port: 51820

peer: gN65BkIKwT6rH0mJ2dPVzxR1aLbcOq5Nf3uYpWvX8Ds=
  endpoint: 82.XX.XX.XX:43721
  allowed ips: 10.8.0.2/32
  latest handshake: 47 seconds ago
  transfer: 2.47 MiB received, 14.82 MiB sent

peer: 7Rp2kLQmVnB9oT1jX5yDfUwS8hAcEi6Zx0GqNpMrJ4k=
  endpoint: 151.XX.XX.XX:51820
  allowed ips: 10.8.0.3/32
  latest handshake: 3 minutes, 12 seconds ago
  transfer: 892.31 KiB received, 4.21 MiB sent
```

**Lettura dei campi:**

| Campo | Significato | Cosa cercare |
|---|---|---|
| `public key` (interface) | Chiave pubblica del server | Deve corrispondere a quella nel file di configurazione dei client |
| `listening port` | Porta UDP su cui WireGuard ascolta | Deve corrispondere al port forwarding del router (51820) |
| `endpoint` | IP:porta corrente del peer | Si aggiorna automaticamente al roaming del client |
| `allowed ips` | Subnet autorizzate per quel peer | `10.8.0.2/32` = solo il suo IP VPN (split tunnel lato server) |
| `latest handshake` | Tempo dall'ultimo handshake completato | Se supera i 5 minuti, la sessione e' scaduta. Se dice `(none)`, il client non si e' mai connesso |
| `transfer` | Byte scambiati (received = dal client, sent = verso il client) | Asimmetria estrema (molto sent, poco received) e' normale: il client naviga e il server inoltra le risposte |

> **Diagnostica rapida:** Se `latest handshake` mostra `(none)` e il client sembra connesso, il problema e' quasi sempre il port forwarding: il pacchetto UDP non raggiunge il server. Verificare che la porta 51820/UDP sia aperta sul router e che UFW non la blocchi (`sudo ufw allow 51820/udp`)
