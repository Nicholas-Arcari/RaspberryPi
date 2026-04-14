>  [Italiano](alternative.md) |  **English**

# Alternatives to Cowrie: Which Honeypot for Which Purpose

Cowrie is an excellent choice for SSH/Telnet, but it does not cover all attack vectors. An analyst should ask: "what am I NOT seeing?"

## Honeypot Comparison for Raspberry Pi

| Honeypot | Protocols | Interaction | RAM | RPi 5 | Use Case |
|---|---|---|---|---|---|
| **Cowrie** | SSH, Telnet | Medium | ~100MB | **Yes** | Captures SSH credentials and commands (our case) |
| **Dionaea** | SMB, HTTP, FTP, MSSQL, MySQL, SIP | Medium | ~200MB | **Yes** | Captures network exploits and binary malware |
| **OpenCanary** | SSH, HTTP, FTP, SMB, MySQL, RDP, SNMP, NTP | Low | ~50MB | **Yes** | Multiple alerts with minimal setup, ideal for detection |
| **T-Pot** | All (20+ combined honeypots) | Mixed | **4-8GB** | No (too heavy) | Complete platform, x86 with resources only |
| **HoneyD** | Any (emulates full TCP/IP stacks) | Low | ~30MB | **Yes** | Emulates entire networks of fake hosts |
| **Artillery** | SSH, FTP, SMTP, MySQL + port monitoring | Low | ~20MB | **Yes** | Honeypot + lightweight IDS, auto-bans IPs |
| **Heralding** | SSH, FTP, Telnet, HTTP, HTTPS, POP3, IMAP, SMTP | Low | ~50MB | **Yes** | Captures credentials only across many protocols |

## Installation: OpenCanary (Multi-Protocol, Lightweight)

OpenCanary is the most versatile alternative to Cowrie on RPi: it emulates many more services with minimal footprint.

```bash
# Installazione via pip
sudo apt install python3-pip python3-dev libssl-dev libffi-dev -y
sudo pip3 install opencanary

# Genera configurazione di default
opencanaryd --copyconfig

# Modifica la configurazione
sudo nano /etc/opencanaryd/opencanary.conf
```

```json
{
    "device.node_id": "raspberrypi-honeypot",
    "ssh.enabled": true,
    "ssh.port": 2222,
    "ssh.version": "SSH-2.0-OpenSSH_6.7p1 Debian-5+deb8u3",
    
    "http.enabled": true,
    "http.port": 8080,
    "http.banner": "Apache/2.4.41 (Ubuntu)",
    "http.skin": "nasLogin",
    
    "ftp.enabled": true,
    "ftp.port": 21,
    "ftp.banner": "FTP server (vsFTPd 3.0.3) ready.",
    
    "smb.enabled": true,
    "smb.port": 445,
    
    "mysql.enabled": true,
    "mysql.port": 3306,
    
    "rdp.enabled": true,
    "rdp.port": 3389,
    
    "snmp.enabled": true,
    "snmp.port": 161,
    
    "logger": {
        "class": "PyLogger",
        "kwargs": {
            "formatters": {
                "plain": {"format": "%(message)s"}
            },
            "handlers": {
                "file": {
                    "class": "logging.FileHandler",
                    "filename": "/var/log/opencanary/opencanary.json"
                }
            }
        }
    }
}
```

```bash
# Avvia OpenCanary
sudo opencanaryd --start

# Verifica che i servizi siano in ascolto
ss -tlnp | grep -E "(2222|8080|21|445|3306|3389)"
```

**Wazuh integration:** Add the log as a JSON source in `ossec.conf`:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/var/log/opencanary/opencanary.json</location>
</localfile>
```

## Installation: Dionaea (Exploit and Malware Capture)

Dionaea specializes in capturing **network exploits** and **binary malware** -- something Cowrie does not do.

```bash
# Installazione via Docker (più pulita)
docker run -d \
    --name dionaea \
    --restart=always \
    -p 20:20 -p 21:21 \
    -p 42:42 -p 69:69/udp \
    -p 80:80 -p 135:135 \
    -p 443:443 -p 445:445 \
    -p 1433:1433 -p 1723:1723 \
    -p 1883:1883 -p 3306:3306 \
    -p 5060:5060 -p 5061:5061 \
    -p 11211:11211 \
    -v /home/pi/dionaea/log:/opt/dionaea/var/log \
    -v /home/pi/dionaea/binaries:/opt/dionaea/var/lib/dionaea/binaries \
    dinotools/dionaea

# I malware catturati vengono salvati in /home/pi/dionaea/binaries/
# con hash SHA-256 come nome file - pronti per analisi con YARA/ClamAV
```

## The Raspberry Pi as a Network TAP: Honeypot + robots.txt

A **Network TAP** (Test Access Point) passively intercepts traffic. An RPi with two network interfaces (Ethernet + USB-Ethernet adapter) can be configured as a transparent TAP.

But the more interesting question: **does a web honeypot with robots.txt to catch malicious crawlers make sense?**

**Yes, and here is how it works:**

Legitimate crawlers (Googlebot, Bingbot) respect `robots.txt`. Malicious crawlers (scrapers, vulnerability scanners, spambots) typically **ignore** it or, worse, use it as a **map of resources to attack** -- if `robots.txt` says "do not visit `/admin`," an attacker will know that `/admin` exists.

```bash
# Installa un web server honeypot leggero
docker run -d \
    --name webhoneypot \
    --restart=always \
    -p 8888:80 \
    -v /home/pi/webhoneypot:/var/www/html \
    nginx:alpine
```

Create the decoy `robots.txt`:

```bash
cat > /home/pi/webhoneypot/robots.txt <<'EOF'
User-agent: *
Disallow: /admin/
Disallow: /wp-admin/
Disallow: /phpmyadmin/
Disallow: /api/v1/users/
Disallow: /backup/database.sql
Disallow: /.env
Disallow: /config/credentials.json
EOF
```

Create trap pages that log every access:

```bash
# Ogni directory "vietata" è in realtà un redirect che logga l'IP
for dir in admin wp-admin phpmyadmin api/v1/users backup; do
    mkdir -p "/home/pi/webhoneypot/$dir"
    cat > "/home/pi/webhoneypot/$dir/index.html" <<HTML
<!-- Honeypot trap page - any access here is suspicious -->
<html><body>Loading...</body></html>
HTML
done
```

With the right nginx configuration (detailed logging), every access to these pages is recorded -- and anyone who reaches them is suspicious by definition (a legitimate user does not visit `/backup/database.sql`). Integrated with Wazuh, this generates immediate alerts.

## Questions an Analyst Should Ask

**"Does Ngrok make sense for a honeypot?"**

Partially. Ngrok adds an intermediary (their servers) that sees all traffic. For a honeypot:
- **Pro**: bypasses CGNAT without calling the ISP
- **Con**: the attacker's source IP is Ngrok's, not the real one (loses forensic value). The URL changes on every restart (free tier). Ngrok might block "malicious" traffic before it reaches your honeypot
- **Better alternative**: Cloudflare Tunnel (fixed URL, free) or ask the ISP to remove CGNAT

**"Is a single honeypot enough?"**

No. An attacker scanning the network who sees ONLY port 2222 open might get suspicious. In production, you deploy **multiple honeypots** on different ports to look like a real server:

```bash
# Stack honeypot "credibile" per un finto server Linux:
# Cowrie        --> :2222 (SSH)
# OpenCanary    --> :80 (HTTP con skin NAS login)
# Dionaea       --> :445 (SMB), :3306 (MySQL)
# + robots.txt  --> :8080 (web con trappole)
```

**"How do I distinguish an attacker from an authorized pentester?"**

In the logs, you cannot. That is why every penetration test must be **documented in advance** with: scope (target IPs/ports), time window, tester's source IP. An alert originating from an IP not on the authorized pentester list should be treated as real.
