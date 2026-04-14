>  [English](alternative.en.md) |  **Italiano**

# Perchè WireGuard e non le alternative: analisi critica

## WireGuard vs Tailscale vs OpenVPN vs ZeroTier vs NordVPN

| Aspetto | WireGuard | Tailscale | OpenVPN | ZeroTier | NordVPN/Surfshark |
|---|---|---|---|---|---|
| **Architettura** | Point-to-point, self-hosted | Mesh P2P, cloud-coordinated | Client-server, self-hosted | Mesh P2P, cloud-coordinated | Client-server, provider-hosted |
| **Livello OSI** | Layer 3 (IP tunnel) | Layer 3 (WireGuard sotto) | Layer 2 o 3 | Layer 2 (Ethernet virtuale) | Layer 3 |
| **Port forwarding necessario** | **Si** (51820/UDP) | **No** (NAT traversal automatico) | **Si** (1194/UDP o 443/TCP) | **No** (NAT traversal) | **No** (server del provider) |
| **Funziona dietro CGNAT** | Solo con Ngrok/tunnel | **Si** (nativo) | Solo con TCP su 443 | **Si** (nativo) | **Si** (server esterno) |
| **Controllo infrastruttura** | Totale (self-hosted) | Parziale (coordination server Tailscale) | Totale | Parziale (root servers ZeroTier) | Nessuno (provider) |
| **Crittografia** | ChaCha20-Poly1305 (fissa) | WireGuard (sotto il cofano) | Configurabile (AES-256, etc.) | ChaCha20 o AES-256 | AES-256 (provider-managed) |
| **Performance** | Eccellente (kernel-space) | Eccellente (usa WireGuard) | Buona (user-space) | Buona | Variabile (dipende dal server) |
| **Costo** | $0 | $0 (3 utenti) / $6/mese (team) | $0 | $0 (25 devices) / $10/mese | ~$3-5/mese |
| **Config complessità** | Media (port forward, DDNS) | **Bassa** (installa e funziona) | Alta (PKI, certificati) | Bassa | Minima (app) |
| **ARM64 RPi** | Si | Si | Si | Si | Solo client |

## Tailscale: come cambierebbe l'architettura del lab

Tailscale usa WireGuard sotto il cofano, ma aggiunge un **coordination server** (Tailscale cloud) che gestisce lo scambio delle chiavi e il NAT traversal automaticamente. L'impatto architetturale è significativo:

```
ARCHITETTURA ATTUALE (WireGuard self-hosted):
    Internet → DDNS → Router (port forward :51820) → RPi → WireGuard container
    Requisiti: IP pubblico (o DMZ dal provider), DDNS, port forwarding

ARCHITETTURA CON TAILSCALE:
    Internet → Tailscale coordination server → NAT hole-punching P2P
    RPi ←──── tunnel WireGuard diretto ────→ Smartphone/Laptop
    Requisiti: NESSUNO (niente port forward, niente DDNS, funziona dietro CGNAT)
```

**Installazione Tailscale sul Raspberry Pi:**

```bash
# Installazione
curl -fsSL https://tailscale.com/install.sh | sh

# Attivazione (apre il browser per login)
sudo tailscale up

# Verifica: mostra l'IP Tailscale assegnato (100.x.x.x)
tailscale ip -4

# Sul client (telefono/laptop): installa Tailscale, login con lo stesso account
# → Tunnel diretto RPi ↔ Client, senza port forwarding
```

**Impatto sui servizi del lab:**

| Servizio | Con WireGuard | Con Tailscale | Differenza |
|---|---|---|---|
| Accesso remoto LAN | Si (full tunnel) | Si (accesso diretto al Pi) | Tailscale: niente split tunnel, solo dispositivi Tailscale |
| **Honeypot esposto** | Port forward :2222 | **Non possibile** (Tailscale non espone porte a Internet) | **Dealbreaker**: Tailscale non è fatto per esporre servizi pubblici |
| Pi-hole da remoto | Si (DNS via tunnel) | Si (imposta Pi come exit node) | Simile |
| Wazuh Dashboard | Si (via tunnel VPN) | Si (via rete Tailscale) | Simile |
| Costo CGNAT | Richiede DMZ dal provider o Ngrok | Nessun costo aggiuntivo | Tailscale vince |

> **Perchè ho scelto WireGuard e non Tailscale:** Il progetto richiede di **esporre l'honeypot su Internet**. Tailscale è progettato per connettere dispositivi privati, non per esporre servizi pubblici. Con Tailscale, la porta 2222 dell'honeypot non sarebbe raggiungibile da attaccanti esterni - vanificando l'intero scopo del progetto. WireGuard self-hosted permette di controllare esattamente quali porte sono esposte e quali no.

> **Quando usare Tailscale:** Se il progetto fosse solo "NAS + accesso remoto" (senza honeypot), Tailscale sarebbe la scelta migliore: zero configurazione di rete, funziona dietro qualsiasi NAT, nessun DDNS necessario.

## NordVPN/Surfshark: perchè non hanno senso per un homelab

Le VPN commerciali (NordVPN, ExpressVPN, Surfshark) risolvono un problema diverso:

| | VPN self-hosted (WireGuard) | VPN commerciale (NordVPN) |
|---|---|---|
| **Scopo** | Accedere alla TUA rete da remoto | Nascondere il TUO traffico al provider |
| **Traffico** | Smartphone → casa tua → Internet | PC → server NordVPN → Internet |
| **Accesso LAN** | Si (puoi raggiungere NAS, Wazuh) | **No** (non sei connesso alla tua LAN) |
| **IP di uscita** | IP di casa tua | IP di NordVPN (diverso paese) |
| **Honeypot** | Puoi esporre servizi | Non puoi esporre nulla |
| **Privacy dal provider** | No (il provider vede il tuo IP) | Si (il provider vede solo traffico verso NordVPN) |

NordVPN non ti fa accedere al Raspberry Pi da remoto. è un servizio per navigare anonimamente, non per gestire un homelab.

## OpenVPN: quando preferirlo a WireGuard

OpenVPN ha un vantaggio specifico: può funzionare su **TCP porta 443**, rendendosi indistinguibile dal traffico HTTPS. Questo è utile in:

- **Reti aziendali** che bloccano tutto tranne HTTP/HTTPS
- **Paesi con censura** che bloccano attivamente i protocolli VPN (Cina, Russia, Iran)
- **Wi-Fi di hotel/aeroporti** con firewall restrittivi

```bash
# Installazione OpenVPN su Docker (alternativa a WireGuard)
docker run -d \
    --name openvpn \
    --restart=always \
    --cap-add=NET_ADMIN \
    -p 443:1194/tcp \
    -v /home/pi/openvpn:/etc/openvpn \
    kylemanna/openvpn

# Inizializzazione PKI (richiede interazione)
docker exec openvpn ovpn_genconfig -u tcp://miodominio.ddns.net:443
docker exec -it openvpn ovpn_initpki

# Genera un client
docker exec openvpn easyrsa build-client-full client1 nopass
docker exec openvpn ovpn_getclient client1 > client1.ovpn
```

Lo svantaggio: ~100.000 righe di codice (vs 4.000 di WireGuard), superficie d'attacco molto più ampia, PKI complessa da gestire.

## Cloudflare Tunnel: l'alternativa a Ngrok per esporre servizi

Se usi Cloudflare per il DNS, **Cloudflare Tunnel** è un'alternativa gratuita e più stabile di Ngrok:

```bash
# Installazione cloudflared
curl -fsSL https://pkg.cloudflare.com/cloudflared-ascii.repo | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install cloudflared -y

# Autenticazione
cloudflared tunnel login

# Crea un tunnel
cloudflared tunnel create homelab-honeypot

# Configura il tunnel per esporre l'honeypot
cat > ~/.cloudflared/config.yml <<EOF
tunnel: <TUNNEL_ID>
credentials-file: /root/.cloudflared/<TUNNEL_ID>.json
ingress:
  - hostname: honeypot.miodominio.com
    service: ssh://localhost:2222
  - service: http_status:404
EOF

# Avvia il tunnel
cloudflared tunnel run homelab-honeypot
```

| | Ngrok | Cloudflare Tunnel |
|---|---|---|
| **Costo** | Gratis (1 tunnel, URL random) | Gratis (illimitati, dominio fisso) |
| **URL** | Cambia ad ogni riavvio (free tier) | Fisso (tuo dominio) | 
| **Protocolli** | TCP, HTTP, HTTPS | HTTP, HTTPS, SSH, TCP |
| **Velocità** | Buona | Eccellente (rete Cloudflare globale) |
| **Persistenza** | Richiede screen/systemd | Servizio systemd nativo |
| **Requisiti** | Account Ngrok | Dominio su Cloudflare (gratuito) |
