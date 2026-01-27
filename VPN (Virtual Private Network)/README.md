# Raspberry Pi VPN Server con WireGuard & Docker

Una guida completa passo-passo per trasformare un Raspberry Pi in un server VPN sicuro, utilizzando WireGuard (tramite wg-easy) su Docker

Questa guida nasce dalla mia esperienza personale e copre non solo l'installazione software, ma anche le complesse configurazioni di rete (DMZ, NAT, DNS) necessarie per far funzionare il tutto dietro un provider con antenna (FWA)

---

## Accenni Teorici

### Cos'è una VPN?

Una VPN (Virtual Private Network) crea un tunnel crittografato tra il tuo dispositivo (smartphone/laptop) e la tua rete di casa. Questo permette di:
- Navigare in sicurezza su Wi-Fi pubblici (tutto il traffico passa crittografato da casa tua)
- Accedere ai dispositivi della rete locale (NAS, Domotica, Stampanti) come se fossi seduto sul divano

### Perché WireGuard?

Rispetto a OpenVPN o IPSec, WireGuard è un protocollo moderno progettato per essere:
- Più veloce: Prestazioni superiori e ping più basso
- Più leggero: Meno consumo di batteria su smartphone
- Più semplice: Configurazione basata su chiavi pubbliche/private

### L'Architettura

Il progetto utilizza Docker per containerizzare il servizio. Nello specifico, uso l'immagine [wg-easy](https://github.com/wg-easy/wg-easy) che offre, oltre al server VPN, una comoda interfaccia Web per generare file di configurazione e QR Code per i client

---

## La sfida della Rete: DMZ e Doppio NAT

Prima di toccare il Raspberry, ho dovuto risolvere un problema critico di rete

### Il Problema
La mia connessione Internet arriva tramite un'antenna FWA (Comeser) collegata al mio router personale (TP-Link). Questo creava una situazione di Doppio NAT:
- NAT dell'Antenna (Provider)
- NAT del Router TP-Link (Casa)

Aprire le porte sul TP-Link non serviva a nulla, perché il traffico veniva bloccato "a monte" dall'antenna del provider

### La Soluzione: DMZ (NAT 1:1)

Ho contattato l'assistenza tecnica del provider chiedendo di mettere l'IP del mio router in DMZ (o abilitare un NAT 1 a 1)
- Risultato: L'antenna ora instrada tutto il traffico in entrata direttamente al mio router TP-Link, bypassando il firewall del provider
- Sicurezza: Dato che il mio router è ora esposto direttamente su Internet, ho disabilitato la gestione remota e impostato password robuste

---

## Prerequisiti

- Hardware: Raspberry Pi (3, 4 o 5) con Raspberry Pi OS
- Rete: IP Pubblico (o DDNS configurato)
  - Accesso amministrativo al Router
  - Porta 51820 UDP aperta verso il Raspberry

---

## Installazione Passo-Passo

### Configurazione Router

1. Indirizzo IP Fisso: Ho assegnato un IP statico al Raspberry (es. `192.168.0.102`) tramite Address Reservation nel router

2. DDNS: Ho registrato un dominio gratuito su [No-IP](https://www.noip.com) e configurato il client DDNS sul router. Questo assicura che il server sia raggiungibile anche se l'IP pubblico cambia

3. Port Forwarding: Ho creato una regola "Virtual Server":
   - Porta: 51820 (Esterna), 51820 (Interna)
   - IP: 192.168.0.102 (nel mio caso è l'indirizzo del raspberry)
   - Protocollo: UDP

### Installazione di Docker sul Raspberry

Se parti da un sistema pulito, ecco i comandi per installare il motore Docker

```bash
# Scarica ed esegue lo script ufficiale di installazione
curl -fsSL [https://get.docker.com](https://get.docker.com) -o get-docker.sh
sudo sh get-docker.sh

# Aggiunge l'utente corrente al gruppo Docker (per non usare sempre sudo)
sudo usermod -aG docker $USER

# Ricarica i permessi del gruppo
newgrp docker
```

### Configurazione di WireGuard (Docker Compose)

Ho creato una cartella dedicata e il file di configurazione

```Bash
mkdir -p ~/wireguard
cd ~/wireguard
nano docker-compose.yml
```

Ecco il contenuto del mio file docker-compose.yml

Nota: Ho dovuto applicare alcune correzioni specifiche (vedi sezione Troubleshooting)

```YAML
version: "3.8"
services:
  wg-easy:
    environment:
      # Il dominio DDNS configurato sul router
      - WG_HOST=miodominio.ddns.net
      
      # Password per accedere alla Web UI (http://IP-Raspberry:51821)
      - PASSWORD=LaMiaPasswordSegreta
      
      - WG_PORT=51820
      - WG_DEFAULT_ADDRESS=10.8.0.x
      
      # DNS impostati su Google (8.8.8.8) per garantire la navigazione
      # Se si usa Pi-hole sulla stessa rete, si può mettere l'IP del Pi-hole qui.
      - WG_DEFAULT_DNS=8.8.8.8
      
      - WG_ALLOWED_IPS=192.168.0.0/24, 10.8.0.0/24, 0.0.0.0/0
      
      # Fix per connessioni mobili: abbassa la dimensione pacchetti
      - WG_MTU=1280

    # IMPORTANTE: Uso la versione 13 per evitare problemi di hash della password
    image: ghcr.io/wg-easy/wg-easy:13
    container_name: wireguard
    volumes:
      - .:/etc/wireguard
    ports:
      - "51820:51820/udp" # Tunnel VPN
      - "51821:51821/tcp" # Interfaccia Web
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
```

### Avvio del Server

```Bash
docker compose up -d
```

Se tutto va bene, il container si avvierà e sarà possibile accedere all'interfaccia web su `http://192.168.0.102:51821`

---

## Troubleshooting: Problemi Riscontrati e Soluzioni

Durante il processo ho incontrato diversi ostacoli. Ecco come li ho risolti per far risparmiare tempo a voi

### Problema 1: Bootloop del container (Errore Password)

Inizialmente, il container si riavviava all'infinito

- Causa: L'ultima versione (latest o v14) di wg-easy obbliga a usare l'hash Bcrypt per la password invece del testo in chiaro
- Soluzione: Ho forzato l'uso della versione 13 nel file docker-compose (image: ghcr.io/wg-easy/wg-easy:13), che accetta ancora password semplici come variabile d'ambiente

### Problema 2: Connesso ma senza Internet (Il limbo)

Il telefono si connetteva alla VPN (handshake ok), ma non caricava nessuna pagina web.

- Causa: Avevo impostato come DNS un indirizzo IP locale (`192.168.0.250`) destinato a un futuro Pi-hole, che però al momento non esisteva. La VPN cercava un server DNS inesistente
- Soluzione: Ho modificato `WG_DEFAULT_DNS=8.8.8.8` nel compose file e, cosa fondamentale, ho rigenerato il client (cancellato e ricreato nell'interfaccia web) per aggiornare le impostazioni sul telefono

### Problema 3: MTU e Reti Mobili

Sotto alcune reti 4G, la connessione risultava instabile

- Soluzione: Ho aggiunto la riga `WG_MTU=1280` nel docker-compose. Questo riduce la dimensione dei pacchetti per evitare frammentazione e blocchi causati dal doppio incapsulamento (VPN + Provider FWA)

---

## Utilizzo

Apri il browser e vai su `http://IP-Raspberry:51821`

Crea un nuovo client (es. "iPhone")

Scarica l'app WireGuard sul telefono

Scansiona il QR Code generato dal sito

Attiva la VPN quando sei fuori casa: navigazione sicura e accesso alla LAN garantiti