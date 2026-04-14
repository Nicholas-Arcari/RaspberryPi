>  [Italiano](protocollo-dns.md) |  **English**

# Theory: How DNS Blocking Works

## The DNS Resolution Process

When you type `www.google.com` in your browser, the operating system must translate that name into an IP address. Here is the resolution chain:

```
Browser -> Local cache -> Hosts file -> Configured DNS server -> Root DNS -> TLD DNS -> Authoritative DNS
```

1. The browser asks the operating system: "What is the IP of `www.google.com`?"
2. The OS checks the local cache and the `/etc/hosts` file (or `C:\Windows\System32\drivers\etc\hosts`)
3. If no answer is found, it sends a **DNS query** to the configured server (typically the router, which in turn forwards it to the ISP's DNS)
4. The recursive DNS resolver resolves the name through the hierarchy (root -> `.com` -> `google.com`) and returns the IP

## Recursive vs Iterative Resolution

This distinction is fundamental to understanding where Pi-hole fits in and why it works.

**Recursive** - the client asks its DNS server and expects the final answer:

```
[Your PC] -- "What is the IP of www.google.com?" --> [Pi-hole / Recursive DNS]
[Your PC] <-- "142.250.180.4" ---------------------- [Pi-hole / Recursive DNS]
```

The client asks **a single question** and receives the complete answer. All the work is done by the recursive resolver (Pi-hole or the ISP's DNS).

**Iterative** - the recursive resolver queries the DNS hierarchy one level at a time:

```
Pi-hole (recursive resolver)                        DNS Servers
        |
        |-- "Where can I find www.google.com?" -----> [Root Server (.)]
        |<-- "I don't know, ask .com: 192.5.6.30" ---+
        |
        |-- "Where can I find www.google.com?" -----> [TLD .com (192.5.6.30)]
        |<-- "I don't know, ask google.com:          -+
        |     216.239.32.10"
        |
        |-- "What is the IP of www.google.com?" ----> [Authoritative google.com]
        |<-- "142.250.180.4, TTL=300" ----------------+
        |
        +-- Cached for 300 seconds
```

The DNS hierarchy has 3 levels:

| Level | Example | How many exist | What they contain |
|---|---|---|---|
| **Root (.)** | `a.root-servers.net` ... `m.root-servers.net` | 13 clusters (anycast, hundreds of physical servers) | Pointers to TLD servers |
| **TLD** | Servers for `.com`, `.org`, `.it`, `.net` | One per TLD | Pointers to authoritative servers for domains |
| **Authoritative** | Servers for `google.com` | One per registered domain | The actual DNS records (IP, MX, etc.) |

## DNS Records: Types and Practical Use Cases

Each domain has different types of records. You can query them with `dig` (installed on almost all Linux systems):

```bash
# A record (IPv4) - the most common, the one Pi-hole blocks
dig A www.google.com +short
# 142.250.180.4

# AAAA record (IPv6)
dig AAAA www.google.com +short
# 2a00:1450:4002:402::2004

# MX record (Mail Exchange) - where to send email for that domain
dig MX google.com +short
# 10 smtp.google.com.

# NS record (Name Server) - who is the authority for that domain
dig NS google.com +short
# ns1.google.com.
# ns2.google.com.

# CNAME record (alias) - a name that points to another name
dig CNAME www.github.com +short
# github.github.io.

# TXT record - free-form text, used for SPF, DKIM, domain verification
dig TXT google.com +short
# "v=spf1 include:_spf.google.com ~all"

# SOA record (Start of Authority) - DNS zone metadata
dig SOA google.com +short
# ns1.google.com. dns-admin.google.com. 2024010100 900 900 1800 60
```

| Record | Type | Content | Practical Use |
|---|---|---|---|
| `A` | IPv4 Address | `142.250.180.4` | Name -> IP translation (the record Pi-hole blocks by responding `0.0.0.0`) |
| `AAAA` | IPv6 Address | `2a00:1450:...` | Same as A, but for IPv6 (Pi-hole also blocks these with `::`) |
| `CNAME` | Alias (Canonical Name) | `github.github.io.` | A domain that points to another domain (the resolver follows the chain) |
| `MX` | Mail Exchange | `10 smtp.google.com.` | Indicates which server receives email. The number is the priority (lower = preferred) |
| `NS` | Name Server | `ns1.google.com.` | Indicates the authoritative servers for the domain |
| `TXT` | Free-form Text | `"v=spf1 ..."` | Domain ownership verification, SPF (anti-spam), DKIM, DMARC |
| `SOA` | Start of Authority | serial, refresh, retry... | DNS zone metadata: serial number, refresh intervals, negative TTL |
| `PTR` | Reverse DNS | `hostname.example.com.` | Reverse resolution: IP -> name. Used for anti-spam verification and readable logs |
| `SRV` | Service | `_sip._tcp.example.com.` | Indicates where to find a specific service (port, protocol, weight) |

## Anatomy of a DNS Packet

Each DNS query typically travels over **UDP port 53** (TCP is used only if the response exceeds 512 bytes or for zone transfers). The packet has this structure:

```
+--+--+--+--+--+--+--+--+--+--+--+--+
|          Header (12 bytes)          |
+--+--+--+--+--+--+--+--+--+--+--+--+
|      Question Section               |  <- "What are you asking?"
+--+--+--+--+--+--+--+--+--+--+--+--+
|      Answer Section                 |  <- "Here is the answer" (empty in queries)
+--+--+--+--+--+--+--+--+--+--+--+--+
|      Authority Section              |  <- "Who is the authority for this domain"
+--+--+--+--+--+--+--+--+--+--+--+--+
|      Additional Section             |  <- Extra useful records (e.g., NS IP)
+--+--+--+--+--+--+--+--+--+--+--+--+
```

**Header (12 fixed bytes):**

| Field | Bits | Purpose |
|---|---|---|
| ID | 16 | Transaction identifier. The response carries the same ID as the query - this is how the client matches answers to questions |
| QR | 1 | 0 = query, 1 = response |
| Opcode | 4 | 0 = standard query, 1 = inverse query, 2 = server status |
| AA | 1 | Authoritative Answer - the responding server is the authority for the domain |
| TC | 1 | Truncated - the response was truncated (exceeds 512 bytes over UDP), the client must retry over TCP |
| RD | 1 | Recursion Desired - the client is asking the server to resolve recursively |
| RA | 1 | Recursion Available - the server supports recursive resolution |
| RCODE | 4 | Response code: 0=NOERROR, 3=NXDOMAIN (domain does not exist), 2=SERVFAIL |

You can inspect a real DNS packet with `dig` in verbose mode:

```bash
dig www.google.com +noall +answer +comments
```

```
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 41532
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; ANSWER SECTION:
www.google.com.    300    IN    A    142.250.180.4
|                   |      |    |    |
|                   |      |    |    +-- The IP address
|                   |      |    +-- Record type
|                   |      +-- Class (IN = Internet)
|                   +-- TTL: 300 seconds of cache
+-- The requested domain
```

## Where Pi-hole Fits In

Pi-hole acts as a **local DNS server**. All DNS queries on the network pass through it:

```
Device -> Pi-hole (192.168.0.250) -> Is the domain on the blocklist?
                                      |-- YES -> Responds 0.0.0.0 (NXDOMAIN / null)
                                      +-- NO  -> Forwards to upstream DNS (8.8.8.8, 1.1.1.1)
```

When an app or web page attempts to load a resource from an advertising or tracking domain (e.g., `ads.doubleclick.net`, `pixel.facebook.com`), Pi-hole responds with a null address. The resource is never downloaded - the ad simply does not appear.

**Advantages over browser-based ad blockers (uBlock Origin, AdBlock):**

| | Pi-hole (DNS-level) | Browser extension |
|---|---|---|
| Protects all devices | Yes (TVs, IoT, smartphones, consoles) | Only the configured browser |
| Blocks app tracking | Yes (apps use DNS) | No (browser traffic only) |
| Performance impact | None (DNS is faster) | Slight overhead per page |
| Bypassable with DoH | Yes (see below) | No |
| Blocks in-video ads (YouTube) | No (same domains as content) | Partially |
