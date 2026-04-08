# VPN Server - WireGuard su Docker con wg-easy

Guida completa per trasformare il Raspberry Pi in un server VPN usando WireGuard. Questa guida nasce dalla mia esperienza diretta e copre non solo l'installazione software, ma anche le complesse configurazioni di rete (DMZ, Double NAT, DDNS) che sono state necessarie per far funzionare il tutto con un provider FWA (Fixed Wireless Access).

---

## Teoria: VPN e WireGuard

### Cos'e' una VPN

Una VPN (Virtual Private Network) crea un **tunnel crittografato** tra un dispositivo remoto (smartphone, laptop) e la rete di casa. Il traffico viaggia incapsulato all'interno di pacchetti cifrati - chiunque intercetti il traffico (ISP, Wi-Fi pubblico, attaccante MITM) vede solo dati illeggibili.

Casi d'uso concreti:

- **Wi-Fi pubblico**: il traffico tra il tuo dispositivo e il router del bar e' in chiaro. Con la VPN, tutto passa cifrato fino a casa tua
- **Accesso remoto alla LAN**: da fuori casa puoi raggiungere il NAS, la dashboard Wazuh, le telecamere, come se fossi collegato via Ethernet
- **Elusione georestrizioni**: il tuo traffico Internet "esce" dall'IP di casa tua, non dall'IP dell'hotel o dell'aeroporto

### Perche' WireGuard e non OpenVPN/IPSec

| Caratteristica | WireGuard | OpenVPN | IPSec/IKEv2 |
|---|---|---|---|
| **Linee di codice** | ~4.000 | ~100.000+ | ~400.000+ |
| **Superficie d'attacco** | Minima (auditabile) | Ampia | Molto ampia |
| **Crittografia** | Fissa, moderna (vedi sotto) | Configurabile (rischio misconfiguration) | Configurabile |
| **Performance** | Eccellente (kernel-space) | Buona (user-space) | Buona |
| **Consumo batteria** | Basso (idle = 0 traffico) | Medio (keepalive continui) | Medio |
| **Setup** | Chiavi pubbliche/private | Certificati PKI | Certificati PKI/PSK |

### Crittografia di WireGuard (per i curiosi)

WireGuard usa una suite crittografica fissa e moderna - nessuna negoziazione, nessuna scelta di cipher suite:

| Funzione | Algoritmo | Scopo |
|---|---|---|
| Key exchange | **Curve25519** (ECDH) | Scambio chiavi Diffie-Hellman su curva ellittica |
| Cifratura simmetrica | **ChaCha20** | Cifratura del tunnel (alternativa ad AES, ottimizzata per CPU senza AES-NI come ARM) |
| MAC (autenticazione) | **Poly1305** | Verifica integrita' e autenticita' dei pacchetti |
| Hashing | **BLAKE2s** | Derivazione chiavi e hashing interno |
| Key derivation | **HKDF** | Derivazione di chiavi di sessione dalle chiavi condivise |

> **Nota su ARM e ChaCha20:** AES-256 e' veloce su CPU x86 con l'istruzione AES-NI hardware. Il Raspberry Pi 5 (Cortex-A76) ha supporto ARMv8 Crypto Extensions, quindi AES e' comunque veloce. Tuttavia, ChaCha20 e' progettato per essere veloce anche senza accelerazione hardware, rendendolo una scelta robusta per qualsiasi piattaforma.

### Noise Protocol Framework: l'handshake IK in dettaglio

WireGuard utilizza il pattern **Noise_IKpsk2** dal Noise Protocol Framework. "IK" significa che l'**Initiator** conosce gia' la chiave pubblica statica del **Responder** (configurata manualmente o via QR code), e il Responder apprende quella dell'Initiator durante l'handshake.

L'intero handshake richiede **1-RTT** (un solo round-trip) e si completa in 2 messaggi:

```
Initiator (client)                              Responder (server)
     │                                               │
     │  Possiede: S_i (statica), E_i (effimera)      │  Possiede: S_r (statica)
     │  Conosce:  S_r_pub (chiave pubblica server)    │
     │                                               │
     ├── Handshake Initiation ──────────────────────►│
     │   [sender_index, E_i_pub,                     │
     │    AEAD(S_i_pub), AEAD(timestamp)]            │
     │                                               │
     │   DH #1: E_i × S_r_pub  (effimera × statica) │
     │   DH #2: S_i × S_r_pub  (statica × statica)  │
     │                                               │
     │◄── Handshake Response ────────────────────────┤
     │   [sender_index, receiver_index, E_r_pub,     │
     │    AEAD(empty)]                               │
     │                                               │
     │   DH #3: E_i × E_r_pub  (effimera × effimera)│
     │   DH #4: S_i × E_r_pub  (statica × effimera) │
     │                                               │
     ├── Transport Data ────────────────────────────►│
     │◄── Transport Data ────────────────────────────┤
```

**Le 4 operazioni Diffie-Hellman:**

| # | Operazione | Scopo |
|---|---|---|
| DH #1 | `E_initiator × S_responder` | Forward secrecy parziale: anche se la chiave statica del client viene compromessa in futuro, questa sessione resta sicura (la chiave effimera e' distrutta) |
| DH #2 | `S_initiator × S_responder` | Autentica l'initiator al responder - conferma che il client possiede la chiave statica dichiarata |
| DH #3 | `E_initiator × E_responder` | **Full forward secrecy**: entrambe le chiavi sono effimere. Anche compromettendo TUTTE le chiavi statiche, il traffico passato resta cifrato |
| DH #4 | `S_initiator × E_responder` | Autentica il responder all'initiator - conferma che il server possiede la chiave statica dichiarata |

Ogni DH produce materiale crittografico che viene mixato progressivamente in una **chaining key** tramite HKDF. Il risultato finale sono due chiavi simmetriche (una per direzione) usate per cifrare i dati con ChaCha20-Poly1305.

**Perche' il timestamp nel primo messaggio:** Il campo `AEAD(timestamp)` serve come protezione anti-replay. Il responder accetta solo handshake con timestamp crescente - un attaccante che cattura e riproduce un pacchetto di handshake vecchio viene rifiutato.

**Rotazione delle chiavi:** Le chiavi di sessione vengono ruotate automaticamente ogni **2 minuti** o dopo **2^64 - 1 pacchetti** (il contatore del nonce ChaCha20). Se non c'e' traffico, WireGuard non invia nulla (a differenza di OpenVPN che manda keepalive) - da qui il basso consumo batteria. Dopo 5 minuti di silenzio, WireGuard considera la sessione scaduta e rinegozia al prossimo pacchetto.

### Cryptokey Routing: l'innovazione architetturale

La vera innovazione di WireGuard non e' la crittografia, ma il concetto di **Cryptokey Routing Table**: una tabella che associa direttamente **subnet di destinazione → chiave pubblica del peer**.

In un VPN tradizionale (OpenVPN, IPSec), il routing e la crittografia sono separati: prima il kernel decide dove mandare il pacchetto (routing table), poi il tunnel lo cifra. In WireGuard, le due operazioni sono **fuse**:

```
Interfaccia wg0 - Cryptokey Routing Table:
┌─────────────────────┬──────────────────────────────────────────────────┬─────────────────────────┐
│ Allowed IPs         │ Peer (chiave pubblica)                          │ Endpoint               │
├─────────────────────┼──────────────────────────────────────────────────┼─────────────────────────┤
│ 10.8.0.2/32         │ gN65BkIK...  (iPhone di Nick)                   │ 82.XX.XX.XX:43721      │
│ 10.8.0.3/32         │ 7Rp2kLQm...  (Laptop lavoro)                   │ 151.XX.XX.XX:51820     │
│ 0.0.0.0/0           │ aF9xMnPq...  (Full tunnel - tutto il traffico) │ 93.XX.XX.XX:38442      │
└─────────────────────┴──────────────────────────────────────────────────┴─────────────────────────┘
```

**Quando un pacchetto viene inviato:**
1. Il kernel riceve un pacchetto destinato a `10.8.0.2` sull'interfaccia `wg0`
2. WireGuard cerca nella Cryptokey Routing Table: `10.8.0.2` matcha la riga con `gN65BkIK...`
3. Il pacchetto viene cifrato con la chiave di sessione derivata dall'handshake con quel peer
4. Il pacchetto cifrato viene incapsulato in UDP e inviato all'endpoint del peer

**Quando un pacchetto viene ricevuto:**
1. WireGuard riceve un pacchetto UDP cifrato
2. Lo decifra con la chiave di sessione del peer mittente (identificato dall'`index` nell'header)
3. Dopo la decifratura, controlla l'IP sorgente del pacchetto interno
4. **Se l'IP sorgente non e' nell'`Allowed IPs` di quel peer, il pacchetto viene scartato silenziosamente** - questo e' il firewall crittografico implicito di WireGuard

Questa architettura rende WireGuard intrinsecamente resistente allo spoofing: un peer non puo' inviare pacchetti fingendo di essere un altro IP, perche' la verifica `IP sorgente ∈ Allowed IPs` e' legata alla chiave crittografica.

### Roaming trasparente

WireGuard aggiorna l'endpoint di un peer **automaticamente**. Se il tuo telefono passa dal Wi-Fi al 4G (cambiando IP pubblico), il server riceve il prossimo pacchetto valido dal nuovo IP, aggiorna l'endpoint nella tabella, e continua senza interruzione. Non serve rinegoziare l'handshake - le chiavi di sessione restano valide indipendentemente dall'IP

---

## La sfida di rete: DMZ e Doppio NAT

### Il problema del Double NAT

Prima di configurare WireGuard, ho dovuto risolvere un problema di rete che bloccava completamente il port forwarding.

La mia connessione Internet arriva tramite un'**antenna FWA** (provider: Comeser) collegata al mio router personale (TP-Link Archer C50). Questo creava una catena:

```
Internet → [Antenna Provider (NAT #1)] → [Router TP-Link (NAT #2)] → [Raspberry Pi]
```

**Cos'e' il CGNAT (Carrier-Grade NAT):** Il provider assegna alla mia antenna un IP **privato** (tipo `10.x.x.x` o `100.64.x.x`) invece di un IP pubblico. Questo significa che il mio router, pur avendo un "IP WAN", ha in realta' un IP che non e' raggiungibile da Internet.

**Come l'ho scoperto:** Controllando l'IP WAN sul router, vedevo un indirizzo `192.168.x.x` - chiaramente un IP privato. Il port forwarding sul TP-Link non serviva a nulla perche' il traffico veniva bloccato a monte, sul NAT del provider.

### La soluzione: DMZ sul provider

Ho contattato l'assistenza tecnica del provider FWA e ho chiesto di mettere l'IP del mio router in **DMZ** (Demilitarized Zone), ovvero di configurare un **NAT 1:1** che inoltra tutto il traffico in ingresso direttamente al mio router, bypassando il firewall del provider.

```
Internet → [Antenna Provider (DMZ → tutto il traffico al mio router)] → [Router TP-Link] → [Raspberry Pi]
```

Dopo questa modifica, il mio router vede un IP WAN pubblico e il port forwarding funziona normalmente.

> **Nota sulla sicurezza:** Con la DMZ attiva, il router e' esposto direttamente su Internet. Ho preso queste precauzioni:
> - Disabilitato la gestione remota del router (no accesso admin dall'esterno)
> - Cambiato la password admin del router con una robusta
> - Aperto solo le porte strettamente necessarie nel port forwarding
> - Monitoraggio attivo con Wazuh degli accessi al Raspberry

---

## Prerequisiti

| Requisito | Dettaglio |
|---|---|
| **Hardware** | Raspberry Pi con Raspberry Pi OS e Docker installato |
| **IP statico locale** | Assegnare un IP fisso al Pi (es. `192.168.0.102`) tramite DHCP reservation sul router |
| **DDNS** | Dominio dinamico (es. No-IP) che punta all'IP pubblico di casa |
| **Port forwarding** | Porta 51820 UDP inoltrata al Raspberry Pi |
| **IP pubblico** | O DMZ configurata sul provider (per CGNAT) |

---

## Configurazione Router

### 1. IP statico per il Raspberry Pi

Sul router (TP-Link → DHCP → Address Reservation):

- MAC Address del Raspberry Pi
- IP riservato: `192.168.0.102`

Questo garantisce che il port forwarding punti sempre all'IP corretto, anche dopo un reboot del Pi.

### 2. DDNS (Dynamic DNS)

L'IP pubblico assegnato dal provider puo' cambiare periodicamente (IP dinamico). Un servizio **DDNS** (Dynamic Domain Name System) associa un nome dominio fisso (es. `miodominio.ddns.net`) all'IP pubblico corrente.

Ho usato **No-IP** (https://www.noip.com):

1. Registrato un account gratuito
2. Creato un hostname (es. `miodominio.ddns.net`)
3. Configurato il client DDNS sul router (TP-Link → Dynamic DNS → No-IP)

Il router aggiorna automaticamente l'associazione dominio → IP ogni volta che l'IP pubblico cambia.

### 3. Port forwarding

Sul router (TP-Link → Forwarding → Virtual Servers):

| Campo | Valore |
|---|---|
| Service Port | 51820 |
| Internal Port | 51820 |
| IP Address | 192.168.0.102 |
| Protocol | **UDP** |

> **Perche' UDP e non TCP:** WireGuard usa esclusivamente UDP. A differenza di OpenVPN che puo' funzionare su TCP (port 443, per sembrare traffico HTTPS), WireGuard e' progettato attorno a UDP per minimizzare la latenza. Il protocollo gestisce internamente la ritrasmissione dei pacchetti persi, senza l'overhead di TCP.

---

## Installazione di WireGuard con Docker

### Creazione della directory

```bash
mkdir -p ~/wireguard
cd ~/wireguard
```

### Docker Compose

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

### Spiegazione dei parametri chiave

**`WG_ALLOWED_IPS`** - Controlla quali destinazioni sono raggiungibili tramite il tunnel VPN:

- `192.168.0.0/24`: solo traffico verso la LAN di casa passa per la VPN (split tunnel)
- `0.0.0.0/0`: TUTTO il traffico passa per la VPN, incluso il browsing web (full tunnel)
- La combinazione che uso include entrambi, dando al client pieno accesso sia alla LAN che a Internet tramite il tunnel

**`WG_MTU=1280`** - Il MTU (Maximum Transmission Unit) e' la dimensione massima di un pacchetto di rete. Il valore standard e' 1500 byte. WireGuard aggiunge un header di ~60-80 byte a ogni pacchetto (encapsulation), quindi il MTU effettivo deve essere ridotto. Con 1280:

```
[IP header: 20B] [UDP header: 8B] [WG header: ~32B] [Payload: 1280B] = ~1340B < 1500B
```

Su reti mobili 4G/5G, il MTU del provider puo' essere gia' ridotto (1400-1420). Se il pacchetto WireGuard supera il MTU del provider, viene frammentato, causando rallentamenti o timeout. 1280 e' il minimo garantito da IPv6 e funziona ovunque.

### Le regole iptables di wg-easy (PostUp/PostDown)

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

### Avvio

```bash
docker compose up -d
```

Web UI raggiungibile su: `http://192.168.0.102:51821`

### Verifica dello stato del tunnel: `wg show`

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

---

## Troubleshooting - Problemi reali e soluzioni

### Problema 1: Container in bootloop (errore password)

**Sintomo:** Il container si riavvia all'infinito. I log (`docker logs wireguard`) mostrano errori relativi all'hash della password.

**Causa:** La versione 14+ di wg-easy ha cambiato il formato della password: non accetta piu' testo in chiaro nella variabile `PASSWORD`, ma richiede un hash Bcrypt pre-generato nella variabile `PASSWORD_HASH`.

**Soluzione:** Ho fissato la versione a **13** nel Docker Compose (`image: ghcr.io/wg-easy/wg-easy:13`), che accetta ancora password in chiaro. Se vuoi usare la v14+, devi:

```bash
# Generare l'hash Bcrypt
docker run -it ghcr.io/wg-easy/wg-easy wgpw 'LaMiaPasswordSegreta'

# Usare il risultato nel compose:
# - PASSWORD_HASH=$$2a$$12$$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# Nota: i $ vanno raddoppiati ($$) nel file YAML per evitare l'escape
```

### Problema 2: Connesso ma senza Internet ("Il limbo")

**Sintomo:** Il telefono si connette alla VPN (handshake completato, traffico visibile), ma nessuna pagina web si carica.

**Causa:** Avevo impostato `WG_DEFAULT_DNS=192.168.0.250` pensando di usare il Pi-hole futuro. Ma il Pi-hole non era ancora installato. Il client VPN inviava le query DNS a un server inesistente.

**Soluzione:** Cambiato a `WG_DEFAULT_DNS=8.8.8.8` (Google DNS) e, **passaggio critico**, ho cancellato e ricreato il client dalla Web UI. Le impostazioni DNS vengono "cotte" nel file di configurazione del client al momento della creazione. Modificare il server-side non aggiorna i client gia' generati.

### Problema 3: Instabilita' su reti mobili 4G

**Sintomo:** Su Wi-Fi di casa, la VPN funziona perfettamente. Su rete mobile 4G, la connessione e' lenta o cade dopo pochi secondi.

**Causa:** Frammentazione dei pacchetti. Il MTU di default di WireGuard (~1420) sommato all'overhead dell'operatore mobile (che incapsula ulteriormente il traffico) superava il MTU fisico del link, causando frammentazione e ritrasmissioni.

**Soluzione:** Aggiunto `WG_MTU=1280` nel Docker Compose. 1280 byte e' il valore piu' conservativo che garantisce la compatibilita' con qualsiasi rete, incluse quelle mobili con tunnel GTP.

---

## Utilizzo quotidiano

1. Apri il browser e vai su `http://<IP_RASPBERRY>:51821`
2. Inserisci la password
3. Clicca **+ New Client** e dai un nome (es. "iPhone", "Laptop-Lavoro")
4. Scarica l'app **WireGuard** sul dispositivo (iOS, Android, Windows, macOS, Linux)
5. Scansiona il **QR Code** generato dalla Web UI (o scarica il file `.conf`)
6. Attiva la VPN quando sei fuori casa

### Test di verifica

Per confermare che la VPN funzioni:

1. Connetti il telefono all'**hotspot cellulare** (simula una rete esterna)
2. Attiva la VPN
3. Prova a raggiungere la Web UI di Portainer (`https://192.168.0.102:9443`)
4. Se si carica, la VPN funziona e hai accesso alla LAN di casa

---

Prossimo step: [ADS Blocker](../ADS%20Blocker/) - Pi-hole come DNS sinkhole per bloccare pubblicita' e tracking.
