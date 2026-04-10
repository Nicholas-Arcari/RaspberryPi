# Fase 1: Reconnaissance - La scoperta delle porte aperte

## Scansione Nmap

Ho lanciato una scansione completa da un altro computer (Kali Linux) verso il Raspberry Pi:

```bash
nmap -sS -p- -T4 -v <IP_RASPBERRY>
```

**Spiegazione dei flag:**

| Flag | Significato | Dettaglio tecnico |
|---|---|---|
| `-sS` | SYN scan (half-open) | Invia un pacchetto SYN, attende SYN-ACK ma non completa l'handshake TCP (non invia ACK). Piu' veloce e meno rumoroso di un connect scan (`-sT`) perche' non stabilisce connessioni complete |
| `-p-` | Scansiona tutte le 65535 porte | Di default Nmap scansiona solo le 1000 porte piu' comuni. `-p-` le scansiona tutte |
| `-T4` | Timing template "aggressive" | Riduce i timeout e aumenta il parallelismo. Valori da T0 (paranoico) a T5 (insane). T4 e' un buon compromesso velocita'/affidabilita' |
| `-v` | Verbose | Mostra le porte man mano che le trova, senza aspettare la fine della scansione |

---

## Il risultato allarmante

Non era aperta solo la porta 2222 (Honeypot), ma un "albero di Natale" di servizi:

| Porta | Servizio | Rischio |
|---|---|---|
| **22** | SSH reale | **CRITICO** - Un attaccante potrebbe tentare brute force sul vero sistema operativo |
| **443** | Wazuh Dashboard | **ALTO** - La pagina di login del SIEM era visibile dall'esterno |
| **2222** | Cowrie Honeypot | Atteso - e' il servizio che vogliamo esporre |
| **9200** | Wazuh Indexer (OpenSearch) | **CRITICO** - API REST del database degli alert, potenzialmente sfruttabile per estrarre informazioni |
| **55000** | Wazuh API | **ALTO** - API di gestione del Manager |

---

## Output completo della scansione

Questo e' l'output reale (anonimizzato) della scansione SYN scan lanciata dalla macchina Kali:

```
Starting Nmap 7.94SVN ( https://nmap.org ) at 2025-XX-XX 14:32 CET
Initiating ARP Ping Scan at 14:32
Scanning 192.168.0.XXX [1 port]
Completed ARP Ping Scan at 14:32, 0.04s elapsed (1 total hosts)
Initiating SYN Stealth Scan at 14:32
Scanning 192.168.0.XXX [65535 ports]
Discovered open port 443/tcp on 192.168.0.XXX
Discovered open port 22/tcp on 192.168.0.XXX
Discovered open port 9200/tcp on 192.168.0.XXX
Discovered open port 2222/tcp on 192.168.0.XXX
Discovered open port 55000/tcp on 192.168.0.XXX
Discovered open port 1514/tcp on 192.168.0.XXX
Discovered open port 1515/tcp on 192.168.0.XXX
Completed SYN Stealth Scan at 14:33, 26.37s elapsed (65535 total ports)
Nmap scan report for 192.168.0.XXX
Host is up (0.00045s latency).
Not shown: 65528 closed tcp ports (reset)
PORT      STATE SERVICE
22/tcp    open  ssh
443/tcp   open  https
1514/tcp  open  fujitsu-dtc
1515/tcp  open  ifor-protocol
2222/tcp  open  EtherNetIP-1
9200/tcp  open  wap-wsp
55000/tcp open  unknown
MAC Address: XX:XX:XX:XX:XX:XX (Raspberry Pi Ltd)

Nmap done: 1 host scanned in 26.41 seconds
           Raw packets sent: 65536 (2.884MB) -- Rcvd: 65536 (2.621MB)
```

**Analisi riga per riga:**

- **ARP Ping Scan**: Nmap prima verifica che l'host sia attivo con un ARP request (Layer 2). Sulla stessa LAN, ARP e' piu' affidabile di ICMP perche' non puo' essere bloccato dal firewall
- **65535 ports**: la scansione completa ha richiesto ~26 secondi. Su ARM64 con connessione locale, T4 e' sufficientemente veloce
- **`closed tcp ports (reset)`**: le porte chiuse rispondono con RST (Reset). Se fossero state `filtered`, non avrebbero risposto affatto - indice di un firewall che fa drop silenzioso
- **`fujitsu-dtc` / `ifor-protocol` / `EtherNetIP-1`**: Nmap assegna nomi ai servizi basandosi sul file `/usr/share/nmap/nmap-services` (mapping porta -> nome storico). Questi nomi sono **ingannevoli** - la porta 1514 non e' realmente Fujitsu, e' il canale eventi Wazuh. La porta 2222 non e' EtherNet/IP, e' Cowrie. Per identificare i servizi reali serve una scansione con version detection (`-sV`)
- **MAC Address: Raspberry Pi Ltd**: il vendor OUI del MAC address identifica immediatamente il dispositivo come Raspberry Pi. Un attaccante sulla stessa LAN sa esattamente cosa sta attaccando

---

## Scansione con version detection

Per confermare i servizi reali dietro ogni porta:

```bash
nmap -sV -p 22,443,1514,1515,2222,9200,55000 192.168.0.XXX
```

```
PORT      STATE SERVICE     VERSION
22/tcp    open  ssh         OpenSSH 8.4p1 Debian 5+deb11u3 (protocol 2.0)
443/tcp   open  ssl/https   nginx 1.25.3
1514/tcp  open  tcpwrapped
1515/tcp  open  tcpwrapped
2222/tcp  open  ssh         OpenSSH 6.0p1 Debian 4+deb7u2 (protocol 2.0)
9200/tcp  open  http        OpenSearch REST API 2.13.0
55000/tcp open  ssl/unknown
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel
```

**Osservazioni critiche da analista:**

1. **Porta 22 vs 2222**: la versione di OpenSSH sulla porta 22 e' `8.4p1` (versione reale del sistema), quella sulla 2222 e' `6.0p1` (versione volutamente vecchia emulata da Cowrie). Un attaccante esperto noterebbe la discrepanza e capirebbe che la 2222 e' un honeypot. Cowrie puo' essere configurato per emulare versioni piu' recenti nel file `cowrie.cfg` (`ssh_version_string`)
2. **OpenSearch 9200**: l'API REST e' raggiungibile. Un `curl https://192.168.0.XXX:9200/_cat/indices` restituirebbe la lista degli indici (inclusi `wazuh-alerts-*`). Senza autenticazione TLS client, chiunque potrebbe leggere gli alert
3. **`tcpwrapped`**: Nmap non riesce a identificare il servizio perche' la connessione viene chiusa dopo l'handshake TCP. Il Wazuh Manager accetta connessioni solo da agenti registrati con certificato valido
4. **nginx 1.25.3**: rivela la versione esatta del reverse proxy del Dashboard. Un attaccante cercherebbe CVE note per quella specifica versione

---

## La causa: DMZ sul router

Avevo inizialmente inserito il Raspberry Pi in **DMZ** sul router per comodita' durante il setup. La DMZ (in un router consumer) significa "inoltra TUTTO il traffico a questo IP" - bypassa completamente il firewall del router e espone ogni servizio del Raspberry direttamente su Internet.

> **Lezione critica:** La DMZ su un router consumer non e' la stessa cosa della "zona demilitarizzata" in un'architettura enterprise. In enterprise, una DMZ e' una rete separata con firewall dedicati e regole granulari. Su un router domestico, "DMZ" = "esponi tutto" - e' l'equivalente di eliminare il firewall.

**MITRE ATT&CK mapping:**
- **T1046 - Network Service Discovery**: Nmap rileva servizi esposti
- **T1190 - Exploit Public-Facing Application**: Se un servizio esposto ha una CVE nota, puo' essere sfruttato
