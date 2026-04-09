# Security Assessment & Hardening - Red Teaming del proprio Lab

Questa e' stata la fase piu' critica e istruttiva dell'intero progetto. Una volta attivi l'Honeypot e il SIEM, ho voluto testarne la sicurezza simulando di essere un attaccante esterno (Red Teaming). L'obiettivo: capire se il mio Raspberry Pi fosse sicuro o se, paradossalmente, avessi appena aperto una porta verso la mia rete domestica.

---

## Metodologia

L'approccio segue il ciclo standard di un penetration test:

1. **Reconnaissance**: scoprire quali servizi sono esposti
2. **Enumeration**: analizzare i servizi per vulnerabilita'
3. **Exploitation**: tentare di sfruttare le debolezze trovate
4. **Post-exploitation**: verificare cosa un attaccante potrebbe fare dopo l'accesso
5. **Remediation**: correggere le vulnerabilita' scoperte

---

## Fase 1: Reconnaissance - La scoperta delle porte aperte

### Scansione Nmap

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

### Il risultato allarmante

Non era aperta solo la porta 2222 (Honeypot), ma un "albero di Natale" di servizi:

| Porta | Servizio | Rischio |
|---|---|---|
| **22** | SSH reale | **CRITICO** - Un attaccante potrebbe tentare brute force sul vero sistema operativo |
| **443** | Wazuh Dashboard | **ALTO** - La pagina di login del SIEM era visibile dall'esterno |
| **2222** | Cowrie Honeypot | Atteso - e' il servizio che vogliamo esporre |
| **9200** | Wazuh Indexer (OpenSearch) | **CRITICO** - API REST del database degli alert, potenzialmente sfruttabile per estrarre informazioni |
| **55000** | Wazuh API | **ALTO** - API di gestione del Manager |

### Output completo della scansione

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
- **`fujitsu-dtc` / `ifor-protocol` / `EtherNetIP-1`**: Nmap assegna nomi ai servizi basandosi sul file `/usr/share/nmap/nmap-services` (mapping porta → nome storico). Questi nomi sono **ingannevoli** - la porta 1514 non e' realmente Fujitsu, e' il canale eventi Wazuh. La porta 2222 non e' EtherNet/IP, e' Cowrie. Per identificare i servizi reali serve una scansione con version detection (`-sV`)
- **MAC Address: Raspberry Pi Ltd**: il vendor OUI del MAC address identifica immediatamente il dispositivo come Raspberry Pi. Un attaccante sulla stessa LAN sa esattamente cosa sta attaccando

#### Scansione con version detection

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

### La causa: DMZ sul router

Avevo inizialmente inserito il Raspberry Pi in **DMZ** sul router per comodita' durante il setup. La DMZ (in un router consumer) significa "inoltra TUTTO il traffico a questo IP" - bypassa completamente il firewall del router e espone ogni servizio del Raspberry direttamente su Internet.

> **Lezione critica:** La DMZ su un router consumer non e' la stessa cosa della "zona demilitarizzata" in un'architettura enterprise. In enterprise, una DMZ e' una rete separata con firewall dedicati e regole granulari. Su un router domestico, "DMZ" = "esponi tutto" - e' l'equivalente di eliminare il firewall.

**MITRE ATT&CK mapping:**
- **T1046 - Network Service Discovery**: Nmap rileva servizi esposti
- **T1190 - Exploit Public-Facing Application**: Se un servizio esposto ha una CVE nota, puo' essere sfruttato

---

## Fase 2: Exploitation - Test funzionale con Hydra

### Attacco brute force all'Honeypot

Dopo aver individuato la porta 2222, ho verificato che l'Honeypot fosse effettivamente funzionante lanciando un attacco brute force con **Hydra** e la wordlist `rockyou.txt`:

```bash
hydra -l root -P /usr/share/wordlists/rockyou.txt -t 4 ssh://<IP_RASPBERRY>:2222
```

**Spiegazione del comando:**

| Parametro | Significato |
|---|---|
| `hydra` | Tool per attacchi brute force su protocolli di rete |
| `-l root` | Username fisso: prova sempre con l'utente "root" |
| `-P .../rockyou.txt` | Wordlist: file con ~14 milioni di password reali trapelate da data breach |
| `-t 4` | 4 thread paralleli (tentativi simultanei) |
| `ssh://<IP>:2222` | Target: servizio SSH sulla porta 2222 (Honeypot) |

### Risultato

```
[2222][ssh] host: <IP_RASPBERRY>   login: root   password: 12345
[2222][ssh] host: <IP_RASPBERRY>   login: root   password: 123456789
[2222][ssh] host: <IP_RASPBERRY>   login: root   password: password
1 of 1 target successfully completed, 3 valid passwords found
```

**Analisi:** Questo **non** e' un fallimento di sicurezza - e' la conferma che Cowrie funziona correttamente. L'Honeypot e' configurato per accettare password deboli comuni, illudendo gli attaccanti (o i bot) di aver ottenuto accesso root. Ogni tentativo viene registrato e inviato a Wazuh.

**MITRE ATT&CK mapping:**
- **T1110.001 - Brute Force: Password Guessing**: Hydra prova password dalla wordlist
- **T1078.001 - Valid Accounts: Default Accounts**: Le password `root/12345` sono credenziali di default

---

## Fase 3: Post-Exploitation - Test di isolamento

### Il problema del "Pivot"

Ho provato a fare un semplice `ping` **dal Raspberry Pi** verso il mio PC personale:

```bash
ping 192.168.0.xxx  # IP del mio PC Windows
```

**Risultato: il ping funzionava.**

### Perche' e' grave

Se un attaccante riuscisse a **evadere dal container Cowrie** (container escape), avrebbe accesso diretto al sistema operativo host (il Raspberry Pi). Da li', potrebbe:

1. Raggiungere qualsiasi dispositivo sulla rete locale (PC, NAS, stampanti)
2. Effettuare lateral movement verso obiettivi piu' pregiati
3. Installare persistence sul Raspberry stesso

Le tecniche di container escape sono documentate:

- **CVE-2019-5736** (runc): sovrascrittura del binario runc dall'interno del container
- **Montaggio del Docker socket**: se il container ha accesso a `/var/run/docker.sock`, puo' creare container privilegiati
- **Kernel exploits**: il container condivide il kernel con l'host - un exploit kernel = escape

> **L'honeypot non era isolato dalla rete. Questo e' il rischio piu' grave dell'intero progetto.**

**MITRE ATT&CK mapping:**
- **T1610 - Deploy Container**: L'attaccante potrebbe creare container malevoli
- **T1021 - Remote Services**: Lateral movement verso altri dispositivi della rete

---

## Fase 4: Remediation - Blindare la rete con UFW

### Abbandonare la DMZ

Ho disabilitato la DMZ sul router e configurato un firewall interno (UFW) per creare una "gabbia" di rete sul Raspberry Pi.

### L'errore dell'ordine delle regole (lezione dolorosa)

Nel primo tentativo di isolare il Raspberry, ho bloccato tutto il traffico verso la rete locale:

```bash
sudo ufw deny out from any to 192.168.0.0/24
```

**Risultato:** Ho tagliato fuori il Raspberry da Internet. Non poteva piu' raggiungere il router/gateway (`192.168.0.1`) per scaricare aggiornamenti o risolvere DNS.

**La spiegazione tecnica:** UFW (e iptables sotto il cofano) valuta le regole **nell'ordine in cui sono state inserite**. La prima regola che fa match decide il destino del pacchetto. Bloccando `192.168.0.0/24`, ho bloccato anche `192.168.0.1` (il gateway) perche' fa parte di quella subnet.

### L'ordine corretto (PRIMA il gateway, POI il blocco)

```bash
# 1. Policy di default: blocca tutto in ingresso
sudo ufw default deny incoming

# 2. ORDINE CRITICO per il traffico in uscita:
#    Prima PERMETTI il gateway (altrimenti non hai Internet)
sudo ufw allow out from any to 192.168.0.1

#    Poi BLOCCA il resto della LAN (impedisce lateral movement)
sudo ufw deny out from any to 192.168.0.0/24

# 3. Permessi in ingresso selettivi (solo dalla LAN locale)
sudo ufw allow from 192.168.0.0/24 to any port 22    # SSH amministrativo
sudo ufw allow from 192.168.0.0/24 to any port 443   # Wazuh Dashboard
```

**Come iptables interpreta queste regole:**

```
Chain OUTPUT:
  Rule 1: -d 192.168.0.1 → ACCEPT    ← Il gateway passa (e' la prima regola)
  Rule 2: -d 192.168.0.0/24 → REJECT  ← Tutto il resto della LAN viene bloccato
  Rule 3: (default policy: ACCEPT)     ← Internet (fuori dalla LAN) funziona normalmente
```

Il pacchetto verso `192.168.0.1` fa match sulla Rule 1 e viene accettato. Un pacchetto verso `192.168.0.50` (un PC della LAN) non fa match sulla Rule 1, fa match sulla Rule 2 e viene bloccato.

---

## Fase 5: Il mistero dell'agente "Disconnected"

### Il problema

Dopo aver configurato UFW con `default deny incoming`, ho notato sulla Dashboard che l'agente Wazuh installato sulla mia macchina Kali risultava "Disconnected", anche se la macchina era accesa e sulla stessa rete.

### La causa

Nella foga di chiudere tutte le porte, avevo bloccato anche le porte di comunicazione Wazuh:

- **Porta 1514/TCP**: canale per gli eventi (gli agenti inviano i log al Manager)
- **Porta 1515/TCP**: canale per la registrazione (enrollment di nuovi agenti)

### La soluzione

```bash
sudo ufw allow from 192.168.0.0/24 to any port 1514 proto tcp  # Canale eventi
sudo ufw allow from 192.168.0.0/24 to any port 1515 proto tcp  # Canale registrazione
```

Limitando l'accesso alla rete locale (`192.168.0.0/24`), solo gli agenti sulla mia LAN possono comunicare con il Manager. Un attaccante da Internet non puo' registrare agenti fasulli o inviare eventi manipolati.

---

## Fase 6: Esposizione su Internet - CGNAT e Ngrok

### Il problema del Double NAT

Quando ho provato ad esporre l'Honeypot su Internet usando il Port Forwarding del router, non funzionava.

**Diagnosi:** Controllando l'IP WAN del router, ho scoperto che era un indirizzo privato (`192.168.x.x`). Il mio provider Internet (connessione FWA con antenna) mi collocava dietro un **CGNAT (Carrier-Grade NAT)**: un livello aggiuntivo di NAT gestito dal provider.

```
Internet → [CGNAT Provider (IP privato)] → [Router TP-Link (IP privato)] → [Raspberry Pi]
            ↑ Qui si blocca il port forwarding
```

In un CGNAT, il mio router non ha un IP pubblico - ha un IP privato assegnato dall'antenna. Anche configurando perfettamente il port forwarding sul TP-Link, il traffico da Internet non raggiunge mai il mio router perche' il NAT del provider lo blocca.

### La soluzione: Ngrok (tunneling)

**Ngrok** crea un tunnel inverso: il Raspberry Pi si connette a un server Ngrok (in uscita - quindi funziona anche dietro CGNAT), e Ngrok assegna un indirizzo pubblico temporaneo che inoltra il traffico al tunnel.

```
Internet → [Server Ngrok (0.tcp.eu.ngrok.io:xxxxx)] ← tunnel TCP ← [Raspberry Pi porta 2222]
```

#### Installazione e utilizzo

```bash
# Installazione
sudo apt install screen -y

# Avviare una sessione persistente con screen
screen

# Avviare il tunnel Ngrok sulla porta dell'Honeypot
ngrok tcp 2222
```

**Perche' `screen`:** Ngrok e' un processo foreground - se chiudi il terminale SSH, Ngrok muore e il tunnel cade. `screen` crea una sessione terminale persistente che continua a girare anche dopo il logout.

- **Detach (uscire senza chiudere):** `CTRL+A` poi `D`
- **Riattaccarsi alla sessione:** `screen -r`

#### Limitazioni del free plan

- L'indirizzo pubblico (es. `0.tcp.eu.ngrok.io:12345`) e la porta **cambiano ad ogni riavvio** del tunnel
- Nessun dominio fisso (richiede piano a pagamento)
- Se il Raspberry si riavvia, bisogna rientrare in screen e riavviare Ngrok manualmente

---

## Test finale: verifica end-to-end

Per confermare che tutto funzionasse in uno scenario reale:

1. Ho scollegato il mio PC di test (Kali) dal Wi-Fi di casa
2. L'ho collegato all'**hotspot del cellulare** (simulando una rete esterna)
3. Ho lanciato la connessione SSH verso l'indirizzo Ngrok:

```bash
ssh root@<indirizzo_ngrok> -p <porta_ngrok>
```

4. L'accesso all'Honeypot e' stato garantito
5. **Immediatamente** sulla Dashboard di Wazuh e' scattato l'allarme "Intrusione Rilevata" (rule 100012, livello 10)

Il sistema e' online, monitorato e funzionante.

### Alert Wazuh generato dall'intrusione

Questo e' l'alert JSON reale (anonimizzato) che Wazuh ha generato nel momento in cui ho effettuato il login sull'Honeypot via Ngrok:

```json
{
  "_index": "wazuh-alerts-4.x-2025.XX.XX",
  "_id": "a3B7xZIBkQr8vN2f_example",
  "_source": {
    "rule": {
      "level": 10,
      "description": "Cowrie: Login success detected on honeypot",
      "id": "100012",
      "mitre": {
        "tactic": ["Initial Access", "Credential Access"],
        "technique": ["T1078 - Valid Accounts", "T1110 - Brute Force"],
        "id": ["T1078", "T1110"]
      },
      "groups": ["cowrie", "honeypot"]
    },
    "agent": {
      "id": "001",
      "name": "raspberrypi",
      "ip": "192.168.0.XXX"
    },
    "data": {
      "cowrie": {
        "eventid": "cowrie.login.success",
        "username": "root",
        "password": "12345",
        "src_ip": "XX.XX.XX.XX",
        "session": "a1b2c3d4e5f6",
        "protocol": "ssh",
        "timestamp": "2025-XX-XXT14:47:23.456789Z"
      }
    },
    "location": "/var/log/cowrie/cowrie.json",
    "timestamp": "2025-XX-XXT14:47:24.001Z",
    "manager": {
      "name": "wazuh-manager"
    },
    "full_log": "{\"eventid\":\"cowrie.login.success\",\"username\":\"root\",\"password\":\"12345\",\"src_ip\":\"XX.XX.XX.XX\",\"session\":\"a1b2c3d4e5f6\",\"protocol\":\"ssh\",\"timestamp\":\"2025-XX-XXT14:47:23.456789Z\"}"
  }
}
```

**Analisi dei campi chiave:**

| Campo | Valore | Significato |
|---|---|---|
| `rule.level` | `10` | Severita' alta (scala 0-15). Livello 10 = attivita' sospetta che richiede attenzione immediata |
| `rule.id` | `100012` | Regola custom definita in `/var/ossec/etc/rules/local_rules.xml` sul Manager |
| `rule.mitre` | T1078, T1110 | Mapping automatico alle tecniche MITRE ATT&CK per contestualizzare l'attacco |
| `data.cowrie.src_ip` | `XX.XX.XX.XX` | IP sorgente dell'attaccante. In questo caso, l'IP pubblico dell'hotspot del cellulare (passato attraverso Ngrok) |
| `data.cowrie.password` | `12345` | Password usata - Cowrie registra **tutte** le credenziali tentate, utili per analisi statistica delle password piu' comuni |
| `data.cowrie.session` | `a1b2c3d4e5f6` | Identificativo univoco della sessione. Permette di correlare tutti gli eventi di una stessa sessione (login, comandi, download) |
| `location` | `/var/log/cowrie/cowrie.json` | File sorgente del log, monitorato dall'agente Wazuh tramite inotify |

---

## Correlazione eventi: dalla scansione all'alert

In un SOC reale, gli eventi non vengono analizzati in isolamento. La correlazione consiste nel collegare eventi apparentemente separati per ricostruire la **kill chain** dell'attaccante. Ecco come i diversi componenti del lab hanno registrato la mia simulazione:

### Timeline dell'attacco simulato

```
T+0s    Nmap SYN scan dalla macchina Kali
        └─ UFW log: 65535 SYN packets da 192.168.0.YYY (Kali)
        └─ Wazuh rule 5710 (livello 3): "Attempt to scan open ports"

T+30s   Hydra brute force sulla porta 2222
        └─ Cowrie log: centinaia di cowrie.login.failed in rapida successione
        └─ Wazuh rule 100011 (livello 5): "Cowrie: Multiple failed login attempts"

T+2m    Hydra trova password valida (root/12345)
        └─ Cowrie log: cowrie.login.success
        └─ Wazuh rule 100012 (livello 10): "Cowrie: Login success on honeypot"

T+2m30s Sessione interattiva: l'attaccante esegue comandi
        └─ Cowrie log: cowrie.command.input (cat /etc/passwd, wget, uname -a)
        └─ Wazuh rule 100013 (livello 8): "Cowrie: Command executed in honeypot"

T+3m    Tentativo di download malware (simulato)
        └─ Cowrie log: cowrie.session.file_download
        └─ Wazuh rule 100014 (livello 12): "Cowrie: File download attempt"
```

### Query di correlazione sulla Dashboard

Per ricostruire l'intera sequenza su Wazuh Dashboard (OpenSearch Dashboards), questa query filtra tutti gli eventi relativi a una singola sessione dell'attaccante:

```
data.cowrie.session: "a1b2c3d4e5f6" OR data.srcip: "XX.XX.XX.XX"
```

Ordinando per `timestamp` ascendente, si ottiene la timeline completa: dal primo tentativo di login fallito, al successo, ai comandi eseguiti nella sessione honeypot, fino all'eventuale download di file. Questo e' esattamente il workflow che un analista SOC L1 seguirebbe durante il triage di un alert reale.

### Correlazione con i log di rete (UFW)

I log di UFW (`/var/log/ufw.log`) completano il quadro con il livello di rete:

```
[UFW BLOCK] IN=eth0 OUT= MAC=XX:XX:XX SRC=XX.XX.XX.XX DST=192.168.0.XXX LEN=44
            TOS=0x00 PREC=0x00 TTL=64 ID=54321 PROTO=TCP SPT=54321 DPT=9200
            WINDOW=1024 RES=0x00 SYN URGP=0
```

**Lettura del log UFW:**

| Campo | Significato |
|---|---|
| `[UFW BLOCK]` | Il pacchetto e' stato bloccato (dopo la remediation) |
| `SRC=XX.XX.XX.XX` | IP sorgente dell'attaccante |
| `DPT=9200` | Porta di destinazione - l'attaccante ha tentato di raggiungere OpenSearch |
| `SYN` | Flag TCP - e' il primo pacchetto di un handshake (scansione) |
| `WINDOW=1024` | Window size tipica di Nmap SYN scan (fingerprint del tool) |

La correlazione tra il `SRC` del log UFW e il `data.cowrie.src_ip` dell'alert Wazuh conferma che lo stesso IP ha prima scansionato le porte (bloccato da UFW su 9200) e poi si e' concentrato sulla porta 2222 (Honeypot, aperta intenzionalmente).

> **Lezione da analista:** Un singolo alert non racconta mai la storia completa. La vera analisi inizia quando si correlano eventi da fonti diverse (firewall, honeypot, SIEM) per ricostruire l'intera catena d'attacco. Questo e' il valore di avere un SIEM centralizzato come Wazuh: tutti i log convergono in un unico punto, rendendo la correlazione possibile.

---

## Riepilogo delle vulnerabilita' trovate e corrette

| # | Vulnerabilita' | Rischio | Soluzione |
|---|---|---|---|
| 1 | DMZ attiva - tutte le porte esposte su Internet | Critico | Rimossa DMZ, configurato port forwarding selettivo |
| 2 | SSH reale (porta 22) esposto su Internet | Critico | UFW: SSH permesso solo dalla LAN |
| 3 | Wazuh Dashboard/API esposti su Internet | Alto | UFW: porte 443/55000/9200 permesse solo dalla LAN |
| 4 | Nessun isolamento di rete del container Honeypot | Alto | UFW: bloccato traffico outbound verso la LAN (tranne gateway) |
| 5 | Porte Wazuh Agent bloccate | Medio | UFW: aperte porte 1514/1515 dalla LAN |
| 6 | CGNAT impedisce port forwarding | N/A (architettura) | Ngrok tunnel come soluzione alternativa |

---

## Threat Model: analisi STRIDE del lab

Un threat model formalizzato identifica **cosa proteggere**, **da chi**, e **come puo' essere attaccato** — prima che succeda. Uso il framework **STRIDE** (Microsoft), che classifica le minacce in 6 categorie.

### Asset da proteggere

| Asset | Valore | Impatto se compromesso |
|---|---|---|
| **Dati NAS** (foto, documenti, backup) | Alto | Perdita dati personali, violazione privacy |
| **Credenziali SSH / chiavi private** | Critico | Accesso completo all'host e a tutti i servizi |
| **Database alert Wazuh** (OpenSearch) | Medio | L'attaccante cancella le prove della sua intrusione |
| **Configurazione rete** (UFW, iptables) | Alto | L'attaccante apre porte o disabilita il firewall |
| **Container Docker** | Medio | Lateral movement se il container viene usato come pivot |
| **Rete domestica** (altri dispositivi) | Alto | L'attaccante raggiunge PC, telefoni, smart TV |

### Superficie d'attacco

```
                        INTERNET
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
      :2222/TCP       :51820/UDP      Ngrok tunnel
      (Honeypot)      (WireGuard)     (fallback)
      ESPOSTA         ESPOSTA         ESPOSTA
           │               │               │
           └───────┬───────┘               │
                   ▼                       │
              Raspberry Pi                 │
           ┌───────────────────────────────┘
           │
    ┌──────┼──────────────────────────┐
    │      ▼                          │
    │  :22 (SSH)     SOLO LAN         │
    │  :80 (OMV)     SOLO LAN         │
    │  :443 (Wazuh)  SOLO LAN         │
    │  :9200 (Index) SOLO LAN         │
    │  :9443 (Port.) SOLO LAN         │
    └─────────────────────────────────┘
```

Porte esposte a Internet: **solo 2** (Honeypot e WireGuard). Tutto il resto e' accessibile solo dalla LAN.

### Attaccanti probabili

| Tipo | Motivazione | Capacita' | Probabilita' |
|---|---|---|---|
| **Bot automatici** (Mirai, scanner SSH) | Aggiungere il Pi a una botnet | Bassa (credenziali comuni, exploit noti) | **Altissima** (24/7, migliaia al giorno) |
| **Script kiddie** | Curiosita', vandalismo | Bassa-Media (tool preconfigurati) | Media |
| **Attaccante mirato** | Accesso ai dati del NAS | Media-Alta (exploit custom, persistence) | Bassa (home lab, non high-value target) |
| **Insider** (chiunque sulla LAN) | Accesso non autorizzato | Alta (gia' dentro la rete) | Bassa (ambiente domestico) |

### Analisi STRIDE per componente

**STRIDE** classifica le minacce in:
- **S**poofing (impersonare un'identita')
- **T**ampering (modificare dati o codice)
- **R**epudiation (negare di aver compiuto un'azione)
- **I**nformation Disclosure (esporre informazioni riservate)
- **D**enial of Service (rendere il servizio indisponibile)
- **E**levation of Privilege (ottenere permessi non autorizzati)

#### Cowrie Honeypot (esposto a Internet)

| Minaccia | Categoria | Scenario concreto | Mitigazione |
|---|---|---|---|
| Container escape | **E** | L'attaccante sfrutta una CVE di runc (es. CVE-2019-5736) per uscire dal container e ottenere root sull'host | Docker aggiornato, container non privilegiato, no Docker socket montato, seccomp + AppArmor attivi |
| Pivot verso LAN | **E** | Dopo il container escape, l'attaccante scansiona la rete locale | UFW: deny outbound verso 192.168.0.0/24 (tranne gateway), VLAN segmentation |
| DoS via flood | **D** | Migliaia di connessioni simultanee esauriscono le risorse del container | Cgroup memory/pids limits, rate limiting su UFW |
| Fingerprinting | **I** | L'attaccante identifica Cowrie dal banner SSH (versione OpenSSH troppo vecchia) e lo evita | Configurare `ssh_version_string` in `cowrie.cfg` con versione plausibile |

#### WireGuard VPN (esposto a Internet)

| Minaccia | Categoria | Scenario concreto | Mitigazione |
|---|---|---|---|
| Chiave privata compromessa | **S** | Se qualcuno ruba la chiave privata di un client, puo' impersonare quel client VPN | Chiavi salvate solo sul dispositivo, revoca immediata dalla Web UI wg-easy |
| Brute force chiave | **S** | Tentare di indovinare la chiave Curve25519 | Impossibile: 2^128 combinazioni, non c'e' negoziazione (il server ignora pacchetti con chiave sbagliata silenziosamente) |
| Credential stuffing Web UI | **E** | Brute force sulla porta 51821 (Web UI di gestione) | Web UI accessibile solo dalla LAN (UFW), password robusta |
| Replay attack | **T** | Catturare e riprodurre pacchetti VPN | WireGuard usa nonce counter monotonicamente crescente: replay vengono scartati |

#### Wazuh SIEM (solo LAN)

| Minaccia | Categoria | Scenario concreto | Mitigazione |
|---|---|---|---|
| Alert tampering | **T** | L'attaccante modifica o cancella gli alert per nascondere la sua attivita' | Accesso Dashboard solo dalla LAN, credenziali robuste, FIM su `/var/ossec/logs/` |
| API abuse | **E** | Accesso non autorizzato all'API Wazuh (porta 55000) per registrare agent fasulli | UFW: porta 55000 solo dalla LAN, autenticazione API con token |
| Information disclosure | **I** | Gli alert contengono password honeypot, IP interni, configurazioni — se leggibili dall'esterno | Porta 9200 (OpenSearch) non esposta a Internet, TLS per tutte le comunicazioni |
| Log injection | **T** | Un agent compromesso invia log falsi al Manager per generare falsi positivi | mTLS: solo agent con certificato firmato dalla stessa CA possono comunicare |

#### NAS / OpenMediaVault (solo LAN)

| Minaccia | Categoria | Scenario concreto | Mitigazione |
|---|---|---|---|
| Data exfiltration | **I** | Dopo un container escape, l'attaccante monta le share SMB e ruba i dati | Container senza accesso ai volumi NAS, SMB con autenticazione, ACL restrittivi |
| Ransomware | **T** | Un malware cifra i file sulle condivisioni di rete | Backup offline periodici (non accessibili via rete), permessi di sola lettura dove possibile |
| Default credentials | **S** | Le credenziali OMV default (`admin/openmediavault`) non sono state cambiate | Cambiare al primo accesso (documentato nella sezione NAS) |

### Rischi residui accettati

Nessun sistema e' sicuro al 100%. Questi sono i rischi che ho consapevolmente accettato:

| Rischio residuo | Perche' lo accetto | Mitigazione parziale |
|---|---|---|
| Kernel exploit = container escape | Impossibile da eliminare senza VM (overhead eccessivo per RPi) | Kernel aggiornato, seccomp, AppArmor |
| Ngrok tunnel = terza parte | Il traffico dell'honeypot transita per i server Ngrok | Nessun dato sensibile transita (solo sessioni honeypot) |
| Self-signed certificates | Non validati da una CA esterna | Accettabile in ambiente domestico, tutti i componenti sullo stesso host |
| Single point of failure | Un solo Pi per tutti i servizi | Backup periodici, MicroSD come recovery boot |
