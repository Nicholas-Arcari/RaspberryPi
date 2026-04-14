>  [Italiano](ftl-engine.md) |  **English**

# Deep Dive: Pi-hole FTL Engine and gravity.db

## FTL (Faster Than Light) - The Core of Pi-hole

Pi-hole is not just a giant `/etc/hosts` file. Its DNS engine is called **FTL (Faster Than Light)** and is a fork of `dnsmasq` with an integrated analysis and logging layer.

How a query is processed:

```
Client (192.168.0.109) -> DNS query "ads.doubleclick.net"
     |
     v
[Pi-hole FTL receives the query on port 53]
     |
     |-- 1. Checks the local cache (previously known responses)
     |       -> HIT: responds immediately (time: ~0.1ms)
     |       -> MISS: continues v
     |
     |-- 2. Checks the whitelist (explicitly allowed domains)
     |       -> If present: forwards to upstream DNS
     |
     |-- 3. Checks gravity.db (the blocked domains database)
     |       -> MATCH: responds with 0.0.0.0 / :: (blocked)
     |       -> NO MATCH: continues v
     |
     |-- 4. Checks regex/wildcard blocklist
     |       -> MATCH: blocks
     |       -> NO MATCH: continues v
     |
     +-- 5. Forwards the query to upstream DNS (8.8.8.8, 1.1.1.1)
             -> Receives the response, caches it, returns it to the client
```

## gravity.db - The SQLite Blocklist Database

All blocklists are downloaded, deduplicated, and stored in a local SQLite database:

```bash
# Inside the Pi-hole container:
docker exec -it pihole sqlite3 /etc/pihole/gravity.db

# Count blocked domains:
sqlite3> SELECT COUNT(*) FROM gravity;
# 79811

# View configured blocklists:
sqlite3> SELECT address, enabled, number FROM adlist;
# https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|1|79811

# Search for a specific domain:
sqlite3> SELECT * FROM gravity WHERE domain = 'ads.doubleclick.net';
```

**Main table structure:**

| Table | Content |
|---|---|
| `gravity` | All blocked domains (union of all blocklists) |
| `adlist` | Blocklist URLs with enabled/disabled status |
| `domainlist` | Manual whitelist and blacklist entries (type 0 = whitelist, type 1 = blacklist) |
| `client` | Clients with custom policies |
| `domain_audit` | Domains flagged for review |

## Regex and Wildcard Blocking

In addition to static blocklists, Pi-hole supports pattern matching:

```bash
# Example: block ALL tracking subdomains
# In the dashboard -> Domains -> RegEx filter:
(^|\.)tracking\..*$

# Block any domain containing "analytics":
.*analytics.*

# Block domains with specific patterns (Microsoft telemetry):
(^|\.)telemetry\.microsoft\.com$
(^|\.)vortex\.data\.microsoft\.com$
```

Regex patterns are compiled at FTL startup and evaluated on every query - too many complex regex patterns can increase DNS latency.

## DNSSEC (Domain Name System Security Extensions)

Pi-hole supports **DNSSEC** validation, which verifies the authenticity of DNS responses through cryptographic signatures.

**The problem DNSSEC solves:** the DNS protocol was designed without authentication. An attacker (DNS spoofing, cache poisoning) can return false responses, redirecting `www.bank.com` to a malicious server. DNSSEC adds digital signatures to DNS responses that the resolver can verify.

**How it works:**

1. The domain (e.g., `example.com`) signs its DNS records with a private key
2. The corresponding public key is published in the DNS itself (DNSKEY record)
3. The resolver verifies the signature: if it matches, the response is authentic; if it does not match, the response is discarded

To enable DNSSEC in Pi-hole: **Settings -> DNS -> Use DNSSEC** (checkbox).

> **Note:** DNSSEC adds a slight latency to the first query (chain of trust verification). If the upstream DNS does not support DNSSEC (or the domain is not signed), the query passes normally without validation - DNSSEC does not break unsigned domains.
