# Deep Dive: Pi-hole FTL Engine e gravity.db

## FTL (Faster Than Light) - il cuore di Pi-hole

Pi-hole non e' un semplice file `/etc/hosts` gigante. Il suo motore DNS si chiama **FTL (Faster Than Light)** ed e' un fork di `dnsmasq` con un layer di analisi e logging integrato.

Come funziona una query:

```
Client (192.168.0.109) → query DNS "ads.doubleclick.net"
     │
     ▼
[Pi-hole FTL riceve la query sulla porta 53]
     │
     ├── 1. Controlla la cache locale (risposte gia' note)
     │       → HIT: risponde immediatamente (tempo: ~0.1ms)
     │       → MISS: prosegue ▼
     │
     ├── 2. Controlla la whitelist (domini esplicitamente permessi)
     │       → Se presente: inoltra al DNS upstream
     │
     ├── 3. Controlla gravity.db (il database dei domini bloccati)
     │       → MATCH: risponde con 0.0.0.0 / :: (blocco)
     │       → NO MATCH: prosegue ▼
     │
     ├── 4. Controlla regex/wildcard blocklist
     │       → MATCH: blocca
     │       → NO MATCH: prosegue ▼
     │
     └── 5. Inoltra la query al DNS upstream (8.8.8.8, 1.1.1.1)
             → Riceve la risposta, la mette in cache, la restituisce al client
```

## gravity.db - il database SQLite delle blocklist

Tutte le blocklist vengono scaricate, deduplicate e archiviate in un database SQLite locale:

```bash
# Dentro il container Pi-hole:
docker exec -it pihole sqlite3 /etc/pihole/gravity.db

# Contare i domini bloccati:
sqlite3> SELECT COUNT(*) FROM gravity;
# 79811

# Vedere le blocklist configurate:
sqlite3> SELECT address, enabled, number FROM adlist;
# https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|1|79811

# Cercare un dominio specifico:
sqlite3> SELECT * FROM gravity WHERE domain = 'ads.doubleclick.net';
```

**Struttura delle tabelle principali:**

| Tabella | Contenuto |
|---|---|
| `gravity` | Tutti i domini bloccati (union di tutte le blocklist) |
| `adlist` | URL delle blocklist con stato enabled/disabled |
| `domainlist` | Whitelist e blacklist manuali (type 0 = whitelist, type 1 = blacklist) |
| `client` | Client con policy personalizzate |
| `domain_audit` | Domini segnalati per revisione |

## Regex e Wildcard Blocking

Oltre alle blocklist statiche, Pi-hole supporta pattern matching:

```bash
# Esempio: bloccare TUTTI i sottodomini di tracking
# Nella dashboard → Domains → RegEx filter:
(^|\.)tracking\..*$

# Bloccare qualsiasi dominio che contiene "analytics":
.*analytics.*

# Bloccare domini con pattern specifici (telemetria Microsoft):
(^|\.)telemetry\.microsoft\.com$
(^|\.)vortex\.data\.microsoft\.com$
```

I regex vengono compilati all'avvio di FTL e valutati su ogni query - troppi regex complessi possono aumentare la latenza DNS.

## DNSSEC (Domain Name System Security Extensions)

Pi-hole supporta la validazione **DNSSEC**, che verifica l'autenticita' delle risposte DNS tramite firma crittografica.

**Il problema che DNSSEC risolve:** il protocollo DNS e' nato senza autenticazione. Un attaccante (DNS spoofing, cache poisoning) puo' restituire risposte false, reindirizzando `www.banca.it` verso un server malevolo. DNSSEC aggiunge firme digitali alle risposte DNS che il resolver puo' verificare.

**Come funziona:**

1. Il dominio (es. `example.com`) firma i suoi record DNS con una chiave privata
2. La chiave pubblica corrispondente e' pubblicata nel DNS stesso (record DNSKEY)
3. Il resolver verifica la firma: se corrisponde, la risposta e' autentica; se non corrisponde, la risposta viene scartata

Per abilitare DNSSEC in Pi-hole: **Settings → DNS → Use DNSSEC** (checkbox).

> **Nota:** DNSSEC aggiunge una leggera latenza alla prima query (verifica della chain of trust). Se il DNS upstream non supporta DNSSEC (o il dominio non e' firmato), la query passa normalmente senza validazione - DNSSEC non rompe i domini non firmati.
