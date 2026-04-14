>  [English](protocollo-dns.en.md) |  **Italiano**

# Teoria: Come funziona il blocco DNS

## Il processo di risoluzione DNS

Quando digiti `www.google.com` nel browser, il sistema operativo deve tradurre quel nome in un indirizzo IP. Ecco la catena di risoluzione:

```
Browser → Cache locale → File hosts → Server DNS configurato → Root DNS → TLD DNS → Authoritative DNS
```

1. Il browser chiede al sistema operativo: "Qual è l'IP di `www.google.com`?"
2. Il SO controlla la cache locale e il file `/etc/hosts` (o `C:\Windows\System32\drivers\etc\hosts`)
3. Se non trova la risposta, invia una **query DNS** al server configurato (tipicamente il router, che a sua volta inoltra al DNS del provider)
4. Il DNS ricorsivo risolve il nome attraverso la gerarchia (root → `.com` → `google.com`) e restituisce l'IP

## Risoluzione ricorsiva vs iterativa

Questa distinzione è fondamentale per capire dove Pi-hole si inserisce e perchè funziona.

**Ricorsiva** - il client chiede al suo DNS server e si aspetta la risposta finale:

```
[Il tuo PC] ── "Qual è l'IP di www.google.com?" ──► [Pi-hole / DNS ricorsivo]
[Il tuo PC] ◄── "142.250.180.4" ───────────────────── [Pi-hole / DNS ricorsivo]
```

Il client fa **una sola domanda** e riceve la risposta completa. Tutto il lavoro lo fa il resolver ricorsivo (Pi-hole o il DNS del provider).

**Iterativa** - il resolver ricorsivo interroga la gerarchia DNS un livello alla volta:

```
Pi-hole (resolver ricorsivo)                        Server DNS
        │
        ├── "Dove trovo www.google.com?" ──────────► [Root Server (.)]
        │◄── "Non lo so, chiedi a .com: 192.5.6.30" ─┘
        │
        ├── "Dove trovo www.google.com?" ──────────► [TLD .com (192.5.6.30)]
        │◄── "Non lo so, chiedi a google.com:       ─┘
        │     216.239.32.10"
        │
        ├── "Qual è l'IP di www.google.com?" ─────► [Authoritative google.com]
        │◄── "142.250.180.4, TTL=300" ──────────────┘
        │
        └── Salva in cache per 300 secondi
```

La gerarchia DNS ha 3 livelli:

| Livello | Esempio | Quanti ne esistono | Cosa contengono |
|---|---|---|---|
| **Root (.)** | `a.root-servers.net` ... `m.root-servers.net` | 13 cluster (anycast, centinaia di server fisici) | Puntatori ai TLD server |
| **TLD** | Server di `.com`, `.org`, `.it`, `.net` | Uno per ogni TLD | Puntatori agli authoritative server dei domini |
| **Authoritative** | Server di `google.com` | Uno per ogni dominio registrato | I record DNS effettivi (IP, MX, etc.) |

## I Record DNS: tipi e casi d'uso pratici

Ogni dominio ha diversi tipi di record. Puoi interrogarli con `dig` (installato su quasi tutti i sistemi Linux):

```bash
# Record A (IPv4) - il più comune, quello che Pi-hole blocca
dig A www.google.com +short
# 142.250.180.4

# Record AAAA (IPv6)
dig AAAA www.google.com +short
# 2a00:1450:4002:402::2004

# Record MX (Mail Exchange) - dove inviare le email per quel dominio
dig MX google.com +short
# 10 smtp.google.com.

# Record NS (Name Server) - chi è l'autorità per quel dominio
dig NS google.com +short
# ns1.google.com.
# ns2.google.com.

# Record CNAME (alias) - un nome che punta a un altro nome
dig CNAME www.github.com +short
# github.github.io.

# Record TXT - testo libero, usato per SPF, DKIM, verifica proprietà
dig TXT google.com +short
# "v=spf1 include:_spf.google.com ~all"

# Record SOA (Start of Authority) - metadati della zona DNS
dig SOA google.com +short
# ns1.google.com. dns-admin.google.com. 2024010100 900 900 1800 60
```

| Record | Tipo | Contenuto | Uso pratico |
|---|---|---|---|
| `A` | Indirizzo IPv4 | `142.250.180.4` | Traduzione nome → IP (il record che Pi-hole blocca rispondendo `0.0.0.0`) |
| `AAAA` | Indirizzo IPv6 | `2a00:1450:...` | Come A, ma per IPv6 (Pi-hole blocca anche questi con `::`) |
| `CNAME` | Alias (Canonical Name) | `github.github.io.` | Un dominio che punta a un altro dominio (il resolver segue la catena) |
| `MX` | Mail Exchange | `10 smtp.google.com.` | Indica quale server riceve le email. Il numero è la priorità (più basso = preferito) |
| `NS` | Name Server | `ns1.google.com.` | Indica i server autoritativi per il dominio |
| `TXT` | Testo libero | `"v=spf1 ..."` | Verifica proprietà dominio, SPF (anti-spam), DKIM, DMARC |
| `SOA` | Start of Authority | serial, refresh, retry... | Metadati della zona DNS: serial number, intervalli di refresh, TTL negativo |
| `PTR` | Reverse DNS | `hostname.example.com.` | Risoluzione inversa: IP → nome. Usato per verifiche anti-spam e log leggibili |
| `SRV` | Service | `_sip._tcp.example.com.` | Indica dove trovare un servizio specifico (porta, protocollo, peso) |

## Anatomia di un pacchetto DNS

Ogni query DNS viaggia tipicamente su **UDP porta 53** (TCP solo se la risposta supera 512 byte o per zone transfer). Il pacchetto ha questa struttura:

```
+--+--+--+--+--+--+--+--+--+--+--+--+
|          Header (12 byte)           |
+--+--+--+--+--+--+--+--+--+--+--+--+
|      Question Section               |  ← "Cosa stai chiedendo?"
+--+--+--+--+--+--+--+--+--+--+--+--+
|      Answer Section                  |  ← "Ecco la risposta" (vuota nelle query)
+--+--+--+--+--+--+--+--+--+--+--+--+
|      Authority Section               |  ← "Chi è l'autorità per questo dominio"
+--+--+--+--+--+--+--+--+--+--+--+--+
|      Additional Section              |  ← Record extra utili (es. IP del NS)
+--+--+--+--+--+--+--+--+--+--+--+--+
```

**Header (12 byte fissi):**

| Campo | Bit | Scopo |
|---|---|---|
| ID | 16 | Identificativo della transazione. La risposta ha lo stesso ID della query - così il client sa a quale domanda corrisponde |
| QR | 1 | 0 = query, 1 = response |
| Opcode | 4 | 0 = standard query, 1 = inverse query, 2 = server status |
| AA | 1 | Authoritative Answer - il server che risponde è l'autorità per il dominio |
| TC | 1 | Truncated - la risposta è stata troncata (supera 512 byte UDP), il client deve riprovare su TCP |
| RD | 1 | Recursion Desired - il client chiede al server di risolvere ricorsivamente |
| RA | 1 | Recursion Available - il server supporta la risoluzione ricorsiva |
| RCODE | 4 | Codice di risposta: 0=NOERROR, 3=NXDOMAIN (dominio non esiste), 2=SERVFAIL |

Puoi vedere un pacchetto DNS reale con `dig` in modalità verbosa:

```bash
dig www.google.com +noall +answer +comments
```

```
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 41532
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; ANSWER SECTION:
www.google.com.    300    IN    A    142.250.180.4
│                   │      │    │    │
│                   │      │    │    └── L'indirizzo IP
│                   │      │    └── Tipo di record
│                   │      └── Classe (IN = Internet)
│                   └── TTL: 300 secondi di cache
└── Il dominio richiesto
```

## Dove si inserisce Pi-hole

Pi-hole si posiziona come **DNS server locale**. Tutte le query DNS della rete passano attraverso di lui:

```
Dispositivo → Pi-hole (192.168.0.250) → Il dominio è in blocklist?
                                          ├── SI → Risponde 0.0.0.0 (NXDOMAIN / null)
                                          └── NO → Inoltra al DNS upstream (8.8.8.8, 1.1.1.1)
```

Quando un'app o una pagina web tenta di caricare una risorsa da un dominio di advertising o tracking (es. `ads.doubleclick.net`, `pixel.facebook.com`), Pi-hole risponde con un indirizzo nullo. La risorsa non viene mai scaricata - la pubblicità semplicemente non appare.

**Vantaggi rispetto ai browser ad-blocker (uBlock Origin, AdBlock):**

| | Pi-hole (DNS-level) | Browser extension |
|---|---|---|
| Protegge tutti i dispositivi | Si (TV, IoT, smartphone, console) | Solo il browser configurato |
| Blocca tracking app | Si (le app usano DNS) | No (solo traffico browser) |
| Impatto performance | Nessuno (il DNS è più veloce) | Leggero overhead per pagina |
| Bypassabile con DoH | Si (vedi sotto) | No |
| Blocca in-video ads (YouTube) | No (stessi domini del contenuto) | Parzialmente |
