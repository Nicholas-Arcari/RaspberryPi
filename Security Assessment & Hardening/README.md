# Security Assessment & Hardening — Red Teaming del proprio Lab

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

## Fase 1: Reconnaissance — La scoperta delle porte aperte

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
| **22** | SSH reale | **CRITICO** — Un attaccante potrebbe tentare brute force sul vero sistema operativo |
| **443** | Wazuh Dashboard | **ALTO** — La pagina di login del SIEM era visibile dall'esterno |
| **2222** | Cowrie Honeypot | Atteso — e' il servizio che vogliamo esporre |
| **9200** | Wazuh Indexer (OpenSearch) | **CRITICO** — API REST del database degli alert, potenzialmente sfruttabile per estrarre informazioni |
| **55000** | Wazuh API | **ALTO** — API di gestione del Manager |

### La causa: DMZ sul router

Avevo inizialmente inserito il Raspberry Pi in **DMZ** sul router per comodita' durante il setup. La DMZ (in un router consumer) significa "inoltra TUTTO il traffico a questo IP" — bypassa completamente il firewall del router e espone ogni servizio del Raspberry direttamente su Internet.

> **Lezione critica:** La DMZ su un router consumer non e' la stessa cosa della "zona demilitarizzata" in un'architettura enterprise. In enterprise, una DMZ e' una rete separata con firewall dedicati e regole granulari. Su un router domestico, "DMZ" = "esponi tutto" — e' l'equivalente di eliminare il firewall.

**MITRE ATT&CK mapping:**
- **T1046 — Network Service Discovery**: Nmap rileva servizi esposti
- **T1190 — Exploit Public-Facing Application**: Se un servizio esposto ha una CVE nota, puo' essere sfruttato

---

## Fase 2: Exploitation — Test funzionale con Hydra

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

**Analisi:** Questo **non** e' un fallimento di sicurezza — e' la conferma che Cowrie funziona correttamente. L'Honeypot e' configurato per accettare password deboli comuni, illudendo gli attaccanti (o i bot) di aver ottenuto accesso root. Ogni tentativo viene registrato e inviato a Wazuh.

**MITRE ATT&CK mapping:**
- **T1110.001 — Brute Force: Password Guessing**: Hydra prova password dalla wordlist
- **T1078.001 — Valid Accounts: Default Accounts**: Le password `root/12345` sono credenziali di default

---

## Fase 3: Post-Exploitation — Test di isolamento

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
- **Kernel exploits**: il container condivide il kernel con l'host — un exploit kernel = escape

> **L'honeypot non era isolato dalla rete. Questo e' il rischio piu' grave dell'intero progetto.**

**MITRE ATT&CK mapping:**
- **T1610 — Deploy Container**: L'attaccante potrebbe creare container malevoli
- **T1021 — Remote Services**: Lateral movement verso altri dispositivi della rete

---

## Fase 4: Remediation — Blindare la rete con UFW

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

## Fase 6: Esposizione su Internet — CGNAT e Ngrok

### Il problema del Double NAT

Quando ho provato ad esporre l'Honeypot su Internet usando il Port Forwarding del router, non funzionava.

**Diagnosi:** Controllando l'IP WAN del router, ho scoperto che era un indirizzo privato (`192.168.x.x`). Il mio provider Internet (connessione FWA con antenna) mi collocava dietro un **CGNAT (Carrier-Grade NAT)**: un livello aggiuntivo di NAT gestito dal provider.

```
Internet → [CGNAT Provider (IP privato)] → [Router TP-Link (IP privato)] → [Raspberry Pi]
            ↑ Qui si blocca il port forwarding
```

In un CGNAT, il mio router non ha un IP pubblico — ha un IP privato assegnato dall'antenna. Anche configurando perfettamente il port forwarding sul TP-Link, il traffico da Internet non raggiunge mai il mio router perche' il NAT del provider lo blocca.

### La soluzione: Ngrok (tunneling)

**Ngrok** crea un tunnel inverso: il Raspberry Pi si connette a un server Ngrok (in uscita — quindi funziona anche dietro CGNAT), e Ngrok assegna un indirizzo pubblico temporaneo che inoltra il traffico al tunnel.

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

**Perche' `screen`:** Ngrok e' un processo foreground — se chiudi il terminale SSH, Ngrok muore e il tunnel cade. `screen` crea una sessione terminale persistente che continua a girare anche dopo il logout.

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

---

## Riepilogo delle vulnerabilita' trovate e corrette

| # | Vulnerabilita' | Rischio | Soluzione |
|---|---|---|---|
| 1 | DMZ attiva — tutte le porte esposte su Internet | Critico | Rimossa DMZ, configurato port forwarding selettivo |
| 2 | SSH reale (porta 22) esposto su Internet | Critico | UFW: SSH permesso solo dalla LAN |
| 3 | Wazuh Dashboard/API esposti su Internet | Alto | UFW: porte 443/55000/9200 permesse solo dalla LAN |
| 4 | Nessun isolamento di rete del container Honeypot | Alto | UFW: bloccato traffico outbound verso la LAN (tranne gateway) |
| 5 | Porte Wazuh Agent bloccate | Medio | UFW: aperte porte 1514/1515 dalla LAN |
| 6 | CGNAT impedisce port forwarding | N/A (architettura) | Ngrok tunnel come soluzione alternativa |
