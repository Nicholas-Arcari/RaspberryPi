# Alternative a Cowrie: quale honeypot per quale scopo

Cowrie e' un'ottima scelta per SSH/Telnet, ma non copre tutti i vettori d'attacco. Un analista deve chiedersi: "cosa NON sto vedendo?"

## Confronto honeypot per Raspberry Pi

| Honeypot | Protocolli | Interazione | RAM | RPi 5 | Caso d'uso |
|---|---|---|---|---|---|
| **Cowrie** | SSH, Telnet | Medium | ~100MB | **Si** | Cattura credenziali e comandi SSH (il nostro caso) |
| **Dionaea** | SMB, HTTP, FTP, MSSQL, MySQL, SIP | Medium | ~200MB | **Si** | Cattura exploit di rete e malware binari |
| **OpenCanary** | SSH, HTTP, FTP, SMB, MySQL, RDP, SNMP, NTP | Low | ~50MB | **Si** | Alert multipli con setup minimo, ideale per detection |
| **T-Pot** | Tutti (20+ honeypot combinati) | Mixed | **4-8GB** | No (troppo pesante) | Piattaforma completa, solo per x86 con risorse |
| **HoneyD** | Qualsiasi (emula stack TCP/IP completi) | Low | ~30MB | **Si** | Emula intere reti di host finti |
| **Artillery** | SSH, FTP, SMTP, MySQL + port monitoring | Low | ~20MB | **Si** | Honeypot + IDS leggero, banna IP automaticamente |
| **Heralding** | SSH, FTP, Telnet, HTTP, HTTPS, POP3, IMAP, SMTP | Low | ~50MB | **Si** | Solo cattura credenziali su molti protocolli |

## Installazione: OpenCanary (multi-protocollo, leggero)

OpenCanary e' l'alternativa piu' versatile a Cowrie su RPi: emula molti piu' servizi con un impatto minimo.

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

**Integrazione con Wazuh:** Aggiungere il log come sorgente JSON in `ossec.conf`:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/var/log/opencanary/opencanary.json</location>
</localfile>
```

## Installazione: Dionaea (cattura exploit e malware)

Dionaea e' specializzato nel catturare **exploit di rete** e **malware binari** -- cosa che Cowrie non fa.

```bash
# Installazione via Docker (piu' pulita)
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

## Il Raspberry Pi come Network TAP: honeypot + robots.txt

Un **Network TAP** (Test Access Point) intercetta passivamente il traffico. Un RPi con due interfacce di rete (Ethernet + USB-Ethernet adapter) puo' essere configurato come TAP trasparente.

Ma la domanda piu' interessante: **ha senso un honeypot web con robots.txt per catturare crawler malevoli?**

**Si, e funziona cosi':**

I crawler legittimi (Googlebot, Bingbot) rispettano `robots.txt`. I crawler malevoli (scraper, vulnerability scanner, spambot) tipicamente lo **ignorano** o, peggio, lo usano come **mappa delle risorse da attaccare** -- se `robots.txt` dice "non visitare `/admin`", un attaccante sapra' che `/admin` esiste.

```bash
# Installa un web server honeypot leggero
docker run -d \
    --name webhoneypot \
    --restart=always \
    -p 8888:80 \
    -v /home/pi/webhoneypot:/var/www/html \
    nginx:alpine
```

Crea il `robots.txt` esca:

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

Crea pagine trappola che loggano ogni accesso:

```bash
# Ogni directory "vietata" e' in realta' un redirect che logga l'IP
for dir in admin wp-admin phpmyadmin api/v1/users backup; do
    mkdir -p "/home/pi/webhoneypot/$dir"
    cat > "/home/pi/webhoneypot/$dir/index.html" <<HTML
<!-- Honeypot trap page - any access here is suspicious -->
<html><body>Loading...</body></html>
HTML
done
```

Con la configurazione nginx giusta (log dettagliati), ogni accesso a queste pagine viene registrato -- e chiunque ci arrivi e' sospetto per definizione (un utente legittimo non visita `/backup/database.sql`). Integrato con Wazuh, genera alert immediati.

## Domande che un analista dovrebbe farsi

**"Ha senso Ngrok per un honeypot?"**

Parzialmente. Ngrok aggiunge un intermediario (i loro server) che vede tutto il traffico. Per un honeypot:
- **Pro**: bypassa CGNAT senza chiamare il provider
- **Contro**: l'IP sorgente degli attaccanti e' quello di Ngrok, non il reale (perde valore forense). L'URL cambia ad ogni riavvio (free tier). Ngrok potrebbe bloccare traffico "malevolo" prima che raggiunga il tuo honeypot
- **Alternativa migliore**: Cloudflare Tunnel (URL fisso, gratuito) o chiedere al provider di rimuovere il CGNAT

**"Un singolo honeypot basta?"**

No. Un attaccante che scansiona la rete e vede SOLO la porta 2222 aperta potrebbe insospettirsi. In produzione, si deployano **honeypot multipli** su porte diverse per sembrare un server reale:

```bash
# Stack honeypot "credibile" per un finto server Linux:
# Cowrie        → :2222 (SSH)
# OpenCanary    → :80 (HTTP con skin NAS login)
# Dionaea       → :445 (SMB), :3306 (MySQL)
# + robots.txt  → :8080 (web con trappole)
```

**"Come distinguo un attaccante da un pentester autorizzato?"**

Nei log, non puoi. Per questo ogni penetration test deve essere **documentato in anticipo** con: scope (IP/porte target), finestra temporale, IP sorgente del tester. Un alert proveniente da un IP non nella lista di pentester autorizzati e' da trattare come reale.
