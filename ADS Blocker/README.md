# Pi-hole - DNS Sinkhole per il blocco di pubblicita' e tracking

Questa guida documenta l'installazione di Pi-hole su Docker con rete MacVLAN, la configurazione del router per usarlo come DNS primario, e i problemi reali che ho incontrato (spoiler: il conflitto della porta 80 con OpenMediaVault).

---

## Teoria: Come funziona il blocco DNS

### Il processo di risoluzione DNS

Quando digiti `www.google.com` nel browser, il sistema operativo deve tradurre quel nome in un indirizzo IP. Ecco la catena di risoluzione:

```
Browser → Cache locale → File hosts → Server DNS configurato → Root DNS → TLD DNS → Authoritative DNS
```

1. Il browser chiede al sistema operativo: "Qual e' l'IP di `www.google.com`?"
2. Il SO controlla la cache locale e il file `/etc/hosts` (o `C:\Windows\System32\drivers\etc\hosts`)
3. Se non trova la risposta, invia una **query DNS** al server configurato (tipicamente il router, che a sua volta inoltra al DNS del provider)
4. Il DNS ricorsivo risolve il nome attraverso la gerarchia (root → `.com` → `google.com`) e restituisce l'IP

### Dove si inserisce Pi-hole

Pi-hole si posiziona come **DNS server locale**. Tutte le query DNS della rete passano attraverso di lui:

```
Dispositivo → Pi-hole (192.168.0.250) → Il dominio e' in blocklist?
                                          ├── SI → Risponde 0.0.0.0 (NXDOMAIN / null)
                                          └── NO → Inoltra al DNS upstream (8.8.8.8, 1.1.1.1)
```

Quando un'app o una pagina web tenta di caricare una risorsa da un dominio di advertising o tracking (es. `ads.doubleclick.net`, `pixel.facebook.com`), Pi-hole risponde con un indirizzo nullo. La risorsa non viene mai scaricata - la pubblicita' semplicemente non appare.

**Vantaggi rispetto ai browser ad-blocker (uBlock Origin, AdBlock):**

| | Pi-hole (DNS-level) | Browser extension |
|---|---|---|
| Protegge tutti i dispositivi | Si (TV, IoT, smartphone, console) | Solo il browser configurato |
| Blocca tracking app | Si (le app usano DNS) | No (solo traffico browser) |
| Impatto performance | Nessuno (il DNS e' piu' veloce) | Leggero overhead per pagina |
| Bypassabile con DoH | Si (vedi sotto) | No |
| Blocca in-video ads (YouTube) | No (stessi domini del contenuto) | Parzialmente |

---

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

![Installer bare metal di Pi-hole - selezione DNS upstream. Questa modalita' di installazione NON va usata con Docker](img/pihole-baremetal-dns-warning.jpg)

![Installer bare metal completato - NON applicabile al nostro setup Docker](img/pihole-baremetal-install-warning.jpg)

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
| Interfaccia fisica RPi5 | `end0` | Ethernet (su RPi5 Bookworm e' `end0`, non `eth0`) |

> **L'IP 192.168.0.250 deve essere fuori dal range DHCP del router.** Se il router assegna IP da `.100` a `.200`, il `.250` e' sicuro. Altrimenti, rischi che il router assegni lo stesso IP a un altro dispositivo, causando conflitti ARP.

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
      parent: end0  # Verificare con 'ip link' - su RPi5 Bookworm e' end0, su RPi4 e' eth0
    ipam:
      config:
        - subnet: 192.168.0.0/24
          gateway: 192.168.0.1
          ip_range: 192.168.0.248/29  # Range .248-.255 riservato a Docker MacVLAN
```

**Spiegazione dei parametri di rete MacVLAN:**

- `parent: end0`: l'interfaccia fisica su cui Docker crea l'interfaccia virtuale MacVLAN
- `ip_range: 192.168.0.248/29`: un piccolo range di 8 IP (`.248` a `.255`) riservato ai container MacVLAN. Questo evita che Docker assegni IP in conflitto con il DHCP del router
- `cap_add: NET_ADMIN`: necessario perche' Pi-hole deve poter modificare la configurazione di rete (binding su porta 53, DHCP se abilitato)

### 3. Avvio e configurazione password

```bash
# Avvio in background
docker compose up -d

# Imposta la password della dashboard
docker exec -it pihole pihole setpassword tua_password_sicura
```

![Dashboard Pi-hole appena avviata - 79.811 domini in blocklist, 0 query (appena installato)](img/pihole-dashboard.jpg)

---

## Configurazione Router e Client

### Configurazione del router come relay DNS

Affinche' **tutti** i dispositivi della rete usino Pi-hole automaticamente, devi dire al router di distribuire l'IP del Pi-hole come DNS tramite DHCP.

Sul router (TP-Link Archer C50 → DHCP → DHCP Settings):

- **Primary DNS**: `192.168.0.250` (IP del Pi-hole)
- **Secondary DNS**: due opzioni:
  - **Hardcore (blocco al 100%)**: lasciare vuoto o `0.0.0.0`. Se Pi-hole va giu', niente Internet - ma nessuna query bypassa il blocco
  - **Failover**: `1.1.1.1` (Cloudflare) o `8.8.8.8` (Google). Se Pi-hole va giu', Internet continua a funzionare, ma alcune query potrebbero bypassare il filtro anche quando Pi-hole e' attivo (il SO potrebbe preferire il DNS secondario per velocita')

![Configurazione DHCP del router - Pi-hole come DNS primario](img/router-dhcp-dns-settings.jpg)

### Perche' i dispositivi non aggiornano subito il DNS

Dopo aver modificato il DNS sul router, i dispositivi non lo usano immediatamente. Il motivo e' il **lease DHCP**: ogni dispositivo ha un "contratto" con il router che include l'indirizzo IP assegnato e il DNS. Questo contratto ha una durata (tipicamente 24 ore). Fino al rinnovo, il dispositivo continua a usare il vecchio DNS.

**Soluzioni:**
- Riavviare il Wi-Fi/Ethernet sul dispositivo (forza un nuovo lease)
- Oppure, su Windows: `ipconfig /release && ipconfig /renew`
- Oppure, su Linux/macOS: `sudo dhclient -r && sudo dhclient`

### Il problema del DNS-over-HTTPS (DoH)

**Attenzione critica:** I browser moderni (Chrome, Edge, Firefox, Brave) possono usare **DNS-over-HTTPS (DoH)**, che invia le query DNS direttamente ai server del browser (es. `dns.google`, `cloudflare-dns.com`) bypassando completamente il DNS del sistema operativo e quindi Pi-hole.

Se vedi ancora pubblicita' dopo la configurazione, controlla:

**Chrome/Edge:** Impostazioni → Privacy e sicurezza → Sicurezza → **Disattiva "Usa DNS sicuro"**

![Chrome - Disabilitazione del DNS sicuro (DoH) per permettere a Pi-hole di funzionare](img/chrome-disable-doh.jpg)

![Pi-hole in azione - blocco attivo delle query di advertising e tracking](img/pihole-blocking-active.jpg)

---

## Verifica del funzionamento

### Dashboard Pi-hole

Accedere a `http://192.168.0.250/admin` e verificare:

- **Total Queries**: il numero deve crescere (ogni dispositivo fa decine di query DNS al minuto)
- **Queries Blocked**: se e' 0 dopo diversi minuti, qualcosa non funziona
- **Percentage Blocked**: tipicamente tra il 15% e il 40% del traffico DNS e' ads/tracking

### Query Log

La sezione **Query Log** mostra ogni singola query DNS in tempo reale:

![Pi-hole Query Log - dettaglio delle query DNS con client, dominio, tipo e stato (Allow/Deny)](img/pihole-query-log.jpg)

Da qui puoi vedere:
- Quale dispositivo ha fatto la query (colonna **Client**)
- Quale dominio e' stato richiesto
- Se e' stato bloccato (rosso) o permesso (verde)
- Il tempo di risposta in millisecondi

### Test con Speedtest

Un test pratico: visita un sito con molte pubblicita' (es. speedtest.net) e osserva la differenza:

![Speedtest.net - le pubblicita' laterali sono visibili perche' il Pi-hole non era ancora configurato come DNS](img/speedtest-ads-visible.jpg)

Dopo aver configurato Pi-hole come DNS, le pubblicita' scompariranno dai siti web. Le aree che ospitavano ads appariranno come spazi vuoti o non verranno caricate affatto.

---

## Troubleshooting

### "I comandi `pihole` non funzionano dal terminale del Pi"

I comandi Pi-hole (`pihole -t`, `pihole status`, ecc.) sono installati **dentro** il container, non sull'host. Dal terminale del Raspberry:

```bash
# Corretto - esegui il comando dentro il container
docker exec -it pihole pihole status

# Errato - il binario non esiste sull'host
pihole status  # Command not found
```

### La dashboard non e' raggiungibile

Verifica che il container sia in esecuzione e che l'IP MacVLAN sia attivo:

```bash
docker ps | grep pihole
docker inspect pihole | grep IPAddress
ping 192.168.0.250  # Da un ALTRO dispositivo (non dal Pi - vedi sotto)
```

### Il Raspberry Pi non raggiunge Pi-hole

Per design di sicurezza del kernel Linux, l'host (Raspberry Pi) **non puo' comunicare** con i container MacVLAN sulla stessa interfaccia (vedi sezione VLAN per la spiegazione tecnica). Questo non e' un bug - e' una feature di sicurezza.

**Conseguenza pratica:** Il Raspberry Pi stesso non puo' usare Pi-hole come DNS. Per un server headless, questo non e' un problema - il Pi non naviga su Internet.

---

## Sviluppi futuri

La struttura MacVLAN permette di aggiungere altri container con IP dedicati sulla rete locale, semplicemente modificando l'indirizzo IP nel Docker Compose:

| Servizio | IP dedicato | Porta |
|---|---|---|
| Pi-hole | 192.168.0.250 | 80, 53 |
| Honeypot | 192.168.0.251 | 2222, 2223 |
| Home Assistant | 192.168.0.252 | 8123 |

---

Prossimo step: [Honeypot](../Honeypot/) - deployment di Cowrie per catturare attaccanti.
