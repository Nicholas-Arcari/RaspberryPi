# Hardening del Raspberry Pi - Guida alla Messa in Sicurezza

Un Raspberry Pi esposto su rete (anche solo LAN) con servizi attivi e' un bersaglio. Questa guida copre le misure di sicurezza fondamentali che ho applicato al mio sistema, spiegando non solo il "come" ma il "perche'" di ogni configurazione.

La filosofia e' **defense in depth**: nessuna singola misura e' sufficiente, ma la combinazione di piu' livelli rende l'attacco significativamente piu' difficile.

---

## 1. Hardening SSH

SSH e' la porta d'ingresso principale al sistema. Se un attaccante compromette SSH, ha accesso completo. Ogni direttiva nel file di configurazione ha un impatto diretto sulla superficie d'attacco.

### Deep Dive: il protocollo SSH dalla connessione TCP all'autenticazione

Per capire le direttive di `sshd_config`, bisogna prima capire cosa succede quando digiti `ssh pi@192.168.0.102`. Il protocollo SSH (RFC 4251-4254) si articola in 5 fasi sequenziali:

```
Client (il tuo PC)                                     Server (Raspberry Pi)
       │                                                       │
       ├──── [FASE 1] TCP Handshake (porta 22) ──────────────►│
       │     SYN → SYN-ACK → ACK                              │
       │                                                       │
       ├──── [FASE 2] Version Exchange ───────────────────────►│
       │     "SSH-2.0-OpenSSH_9.7"                             │
       │◄─── "SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3" ───────┤
       │                                                       │
       ├──── [FASE 3] Key Exchange (KEX) ─────────────────────►│
       │     Lista algoritmi supportati (KEX, cifratura,       │
       │     MAC, compressione) → negoziazione                 │
       │                                                       │
       │     Diffie-Hellman (curve25519-sha256):               │
       │     Client genera e_c (effimera), invia Q_c = e_c*G  │
       │◄─── Server genera e_s, invia Q_s = e_s*G + host_key ─┤
       │                                                       │
       │     Entrambi calcolano: K = e_c * Q_s = e_s * Q_c    │
       │     (shared secret identico, mai trasmesso)           │
       │                                                       │
       │     H = hash(V_c, V_s, I_c, I_s, K_s, Q_c, Q_s, K)  │
       │     Il server FIRMA H con la sua host key privata     │
       │     e invia la firma al client                        │
       │                                                       │
       │     → Session keys derivate da K e H tramite SHA-256  │
       │     → Da questo momento TUTTO il traffico e' cifrato  │
       │                                                       │
       ├──── [FASE 4] Canale cifrato stabilito ───────────────►│
       │     NEWKEYS → entrambi i lati switchano alle nuove    │
       │     chiavi di sessione                                │
       │                                                       │
       ├──── [FASE 5] User Authentication ────────────────────►│
       │     (vedi sotto: password o chiave pubblica)          │
       │                                                       │
```

#### Fase 2: Version Exchange

I primi byte scambiati su una connessione SSH sono **testo in chiaro** - non ancora cifrati. Entrambi i lati inviano la stringa di versione nel formato `SSH-protoversion-softwareversion`:

```
SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3
│    │   │              │
│    │   │              └── Patch del pacchetto Debian
│    │   └── Software e versione (information disclosure!)
│    └── Versione del protocollo (2.0)
└── Identificatore del protocollo
```

> **Implicazione di sicurezza:** Questa stringa e' visibile a chiunque si connetta alla porta 22. Rivela il software, la versione, e il sistema operativo. Un attaccante usa queste informazioni per cercare CVE specifiche. Per questo Cowrie emula una versione diversa (`OpenSSH_6.0p1`) - per sembrare un bersaglio appetibile.

#### Fase 3: Key Exchange (Diffie-Hellman su Curve25519)

Questa e' la fase piu' critica. Il client e il server devono concordare una **chiave segreta condivisa** senza mai trasmetterla sulla rete. Usano il protocollo Diffie-Hellman sulla curva ellittica Curve25519:

**La matematica (semplificata):**

1. Entrambi conoscono una curva ellittica `E` e un punto generatore `G` (parametri pubblici di Curve25519)
2. Il **client** genera un numero casuale `e_c` (chiave effimera privata) e calcola `Q_c = e_c * G` (moltiplicazione scalare sul punto della curva). Invia `Q_c` al server
3. Il **server** genera `e_s` e calcola `Q_s = e_s * G`. Invia `Q_s` al client
4. Il **client** calcola `K = e_c * Q_s = e_c * e_s * G`
5. Il **server** calcola `K = e_s * Q_c = e_s * e_c * G`
6. `K` e' identico su entrambi i lati (proprieta' commutativa della moltiplicazione scalare), ma **non e' mai transitato sulla rete**

Un attaccante che intercetta `Q_c` e `Q_s` dovrebbe risolvere il **Problema del Logaritmo Discreto su Curva Ellittica (ECDLP)** per ricavare `e_c` o `e_s` - computazionalmente impossibile con le dimensioni di Curve25519 (256 bit → sicurezza ~128 bit).

**Session Key derivation:** Dal segreto condiviso `K` e dall'hash di sessione `H`, SSH deriva 6 chiavi separate usando SHA-256:

| Chiave | Scopo |
|---|---|
| `IV_c→s` | Initialization Vector per cifratura client → server |
| `IV_s→c` | Initialization Vector per cifratura server → client |
| `Enc_c→s` | Chiave di cifratura client → server (ChaCha20 o AES-256) |
| `Enc_s→c` | Chiave di cifratura server → client |
| `MAC_c→s` | Chiave HMAC per integrita' client → server |
| `MAC_s→c` | Chiave HMAC per integrita' server → client |

Chiavi separate per ogni direzione prevengono attacchi di reflection (un attaccante che reinvia pacchetti del client al client stesso).

### Host Keys vs User Keys: la distinzione fondamentale

SSH usa **due tipi di chiavi asimmetriche** per scopi completamente diversi. Confonderli e' un errore comune.

#### Host Keys (chiavi del server)

```
/etc/ssh/ssh_host_ed25519_key       ← Chiave PRIVATA del server (permessi 600)
/etc/ssh/ssh_host_ed25519_key.pub   ← Chiave PUBBLICA del server
/etc/ssh/ssh_host_rsa_key           ← Stessa cosa, algoritmo RSA
/etc/ssh/ssh_host_ecdsa_key         ← Stessa cosa, algoritmo ECDSA
```

- **Generate automaticamente** al primo avvio di `sshd` (o durante l'installazione dell'OS)
- Servono ad **autenticare il server al client** - "sei davvero il mio Raspberry Pi, o un impostore?"
- Il server firma l'hash di sessione `H` con la host key privata durante il KEX (Fase 3)
- Il client verifica la firma usando la host key pubblica salvata in `~/.ssh/known_hosts`
- **Se cambiano** (reinstallazione OS, diverso dispositivo sullo stesso IP): l'avviso "REMOTE HOST IDENTIFICATION HAS CHANGED"

#### User Keys (chiavi dell'utente)

```
~/.ssh/id_ed25519       ← Chiave PRIVATA dell'utente (protetta da passphrase)
~/.ssh/id_ed25519.pub   ← Chiave PUBBLICA dell'utente (copiata sul server)
```

- **Generate dall'utente** con `ssh-keygen`
- Servono ad **autenticare l'utente al server** - "sei davvero Nick, o un impostore?"
- La chiave pubblica viene copiata in `~/.ssh/authorized_keys` sul server
- La chiave privata **non lascia mai il client**

### Il Fingerprint: cos'e', come si genera, come si verifica

Quando ti connetti a un server SSH per la prima volta:

```
The authenticity of host '192.168.0.102 (192.168.0.102)' can't be established.
ED25519 key fingerprint is SHA256:xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0=.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Cos'e' il fingerprint:**

```
Chiave pubblica del server (Ed25519, 256 bit)
    │
    ▼ SHA-256 hash
[32 byte di hash]
    │
    ▼ Base64 encode
"xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0="
    │
    ▼ Prefisso algoritmo
"SHA256:xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0="
```

E' un **hash della chiave pubblica del server**, presentato in formato compatto per la verifica umana. Verificare 43 caratteri Base64 e' fattibile; verificare 256 bit di chiave raw sarebbe impraticabile.

**Come verificarlo manualmente (sul server):**

```bash
# Mostra il fingerprint della host key Ed25519
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# 256 SHA256:xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0= root@raspberrypi (ED25519)
```

Se hai accesso fisico al Pi (o una sessione SSH gia' trusted), puoi confrontare questo output con il fingerprint presentato dal client. Se corrispondono, la connessione e' autentica.

> **In pratica:** nella maggior parte dei setup domestici, la prima connessione avviene sulla stessa LAN, dove un attacco MitM e' poco probabile. Ma in ambienti enterprise o su reti non fidate, la verifica del fingerprint e' obbligatoria - idealmente il fingerprint viene comunicato su un canale separato (es. di persona, via telefono, su un documento interno).

**Formato legacy MD5:** Le versioni piu' vecchie di OpenSSH mostravano il fingerprint in formato MD5 esadecimale:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E md5
# 256 MD5:a1:b2:c3:d4:e5:f6:a7:b8:c9:d0:e1:f2:a3:b4:c5:d6 root@raspberrypi (ED25519)
```

Il formato SHA256/Base64 e' preferito perche' SHA-256 e' resistente alle collisioni (trovare due chiavi con lo stesso hash e' computazionalmente impossibile), mentre MD5 ha collisioni note dal 2004.

### Il file `known_hosts`: la Trust-On-First-Use (TOFU) database

Quando accetti il fingerprint ("yes"), il client salva l'associazione in `~/.ssh/known_hosts`:

```
|1|base64salt=|base64hash= ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Formato dei campi:

| Campo | Significato |
|---|---|
| `\|1\|base64salt=\|base64hash=` | **Hashed hostname** - l'IP/hostname del server, offuscato con HMAC-SHA1 per privacy (un attaccante che ruba il file non puo' enumerare i server a cui ti connetti) |
| `ssh-ed25519` | Tipo di chiave |
| `AAAAC3NzaC1...` | Chiave pubblica completa in Base64 |

Ad ogni connessione successiva, il client:
1. Cerca l'hostname nel file `known_hosts`
2. Confronta la chiave pubblica presentata dal server con quella salvata
3. **Match** → connessione procede silenziosamente
4. **Mismatch** → "REMOTE HOST IDENTIFICATION HAS CHANGED" (possibile MitM)
5. **Non trovato** → chiede di accettare il fingerprint (prima connessione)

Questo modello si chiama **TOFU (Trust-On-First-Use)**: ti fidi della prima connessione e verifichi che le successive siano coerenti. E' piu' debole di una PKI (dove un'autorita' certifica l'identita'), ma piu' pratico per SSH.

### Il file `authorized_keys`: formato e meccanismo

Sul server, `~/.ssh/authorized_keys` contiene le chiavi pubbliche degli utenti autorizzati:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx nick@homelab
│            │                                                                    │
│            └── Chiave pubblica (Base64)                                         └── Commento (opzionale)
└── Tipo di chiave
```

Opzioni avanzate (prefisso alla chiave):

```
command="/usr/bin/rsync",no-pty,no-port-forwarding ssh-ed25519 AAAAC3...  backup@nas
```

| Opzione | Effetto |
|---|---|
| `command="..."` | Forza l'esecuzione di un solo comando (es. backup automatici) |
| `no-pty` | Impedisce l'allocazione di un terminale interattivo |
| `no-port-forwarding` | Impedisce il tunneling SSH |
| `from="192.168.0.0/24"` | Accetta la chiave solo da IP nella subnet specificata |

### Autenticazione con chiave pubblica: il challenge-response

Quando `PasswordAuthentication no` e `PubkeyAuthentication yes`, ecco cosa succede nella Fase 5:

```
Client                                              Server
   │                                                    │
   ├── "Voglio autenticarmi come pi                     │
   │    con chiave ssh-ed25519 AAAA..."  ──────────────►│
   │                                                    │
   │    Il server cerca AAAA... in                      │
   │    ~pi/.ssh/authorized_keys                        │
   │                                                    │
   │    Se trovata:                                     │
   │◄── Challenge: dati random cifrati  ────────────────┤
   │    con la chiave pubblica del client               │
   │                                                    │
   │    Il client FIRMA il challenge                    │
   │    con la sua chiave PRIVATA                       │
   │    (la chiave privata non viene MAI inviata)       │
   │                                                    │
   │── Signature(challenge, private_key)  ─────────────►│
   │                                                    │
   │    Il server VERIFICA la firma                     │
   │    usando la chiave pubblica                       │
   │    in authorized_keys                              │
   │                                                    │
   │    Firma valida?                                   │
   │    SI → accesso consentito                         │
   │    NO → accesso negato                             │
   │                                                    │
   │◄── SSH_MSG_USERAUTH_SUCCESS  ──────────────────────┤
```

**Il punto cruciale:** la chiave privata non attraversa mai la rete. Il server invia una sfida (challenge), il client la firma con la chiave privata, il server verifica la firma con la chiave pubblica. Questo e' il principio fondamentale della crittografia asimmetrica applicata all'autenticazione: **la conoscenza della chiave pubblica permette di verificare, ma non di forgiare, una firma**.

Anche se un attaccante intercettasse l'intera sessione, otterrebbe solo la firma di quel challenge specifico - non la chiave privata, e non una firma riutilizzabile (ogni challenge e' unico).

### Configurazione

```bash
sudo nano /etc/ssh/sshd_config
```

Ecco le direttive critiche con la spiegazione di ciascuna:

```bash
# Forza il protocollo SSH versione 2
# SSH v1 ha vulnerabilita' note (CRC-32 compensation attack) ed e' deprecato
Protocol 2

# Disabilita il login diretto come root
# Un attaccante deve prima indovinare un username valido, poi fare privilege escalation
# Riduce drasticamente l'efficacia dei bot che provano root/admin automaticamente
PermitRootLogin no

# Disabilita l'autenticazione tramite password
# Le password sono vulnerabili a brute force. Le chiavi SSH usano crittografia asimmetrica
# (RSA 4096-bit o Ed25519) che rende il brute force computazionalmente impossibile
PasswordAuthentication no

# Abilita l'autenticazione tramite chiave pubblica
# Il client dimostra di possedere la chiave privata corrispondente alla pubblica
# registrata sul server, senza mai trasmettere la chiave privata sulla rete
PubkeyAuthentication yes

# Tempo massimo per completare il login (in secondi)
# Previene connessioni SSH "appese" che occupano risorse
LoginGraceTime 120

# Verifica che i permessi di ~/.ssh siano corretti
# Se authorized_keys e' leggibile da altri utenti, SSH rifiuta di usarlo
StrictModes yes

# Disabilita autenticazione basata su host (legacy, insicura)
HostbasedAuthentication no

# Rifiuta password vuote
PermitEmptyPasswords no

# Disabilita X11 forwarding se non necessario
# Riduce la superficie d'attacco - X11 ha una storia di vulnerabilita'
X11Forwarding no

# Disabilita TCP forwarding - previene l'uso del Pi come proxy
AllowTcpForwarding no

# Disabilita compressione - previene attacchi di tipo CRIME/BREACH
Compression no

# Limita l'accesso SSH solo a utenti nei gruppi specificati
AllowGroups root _ssh

# Percorsi dei file authorized_keys (OMV aggiunge il suo)
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /var/lib/openmediavault/ssh/authorized_keys/
```

La configurazione completa sul mio sistema (generata da OpenMediaVault):

```bash
# This file is auto-generated by openmediavault
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 120
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
X11Forwarding yes
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
UsePAM yes
AllowGroups root _ssh
AddressFamily any
Port 22
PermitRootLogin no
AllowTcpForwarding no
Compression no
PasswordAuthentication no
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /var/lib/openmediavault/ssh/authorized_keys/
PubkeyAuthentication yes
```

> **Nota importante su OMV:** OpenMediaVault rigenera automaticamente `sshd_config` ad ogni modifica dalla sua web UI. Se modifichi il file a mano, le modifiche sopravvivono finche' non tocchi le impostazioni SSH dalla dashboard OMV. Per modifiche permanenti, e' meglio usare la web UI di OMV (Services → SSH) dove possibile.

### Applicare le modifiche

```bash
sudo systemctl restart ssh
```

> **Prima di riavviare SSH:** apri una **seconda sessione SSH** e tienila aperta. Se la nuova configurazione ha un errore (es. `AuthorizedKeysFile` punta a un percorso sbagliato), la sessione corrente resterebbe attiva e potresti correggere l'errore. Altrimenti rischi di chiuderti fuori dal sistema.

### Setup chiave pubblica (se non ancora fatto)

Sul **client** (il tuo PC):

```bash
# Genera una coppia di chiavi Ed25519 (piu' sicura e veloce di RSA)
ssh-keygen -t ed25519 -C "nick@homelab"

# Copia la chiave pubblica sul Raspberry Pi
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@<IP_DEL_RASPBERRY>
```

**Perche' Ed25519 e non RSA:**

| Algoritmo | Dimensione chiave | Sicurezza equivalente | Performance |
|---|---|---|---|
| RSA 2048 | 2048 bit | ~112 bit | Lenta generazione e verifica |
| RSA 4096 | 4096 bit | ~140 bit | Molto lenta |
| Ed25519 | 256 bit | ~128 bit | Velocissima, resistente a side-channel |

Ed25519 usa la curva ellittica Curve25519 e fornisce sicurezza equivalente a RSA 3000+ bit con chiavi molto piu' corte e operazioni crittografiche piu' veloci.

---

## 2. Fail2ban - Protezione Brute Force

**Fail2ban** monitora i log di sistema (es. `/var/log/auth.log`) alla ricerca di pattern di attacco (tentativi di login falliti) e banna automaticamente gli IP offensivi tramite regole firewall.

### Come funziona internamente

1. **Filter**: una regex che identifica un tentativo fallito nei log (es. `Failed password for .* from <HOST>`)
2. **Jail**: la policy - quanti tentativi (`maxretry`), in quanto tempo (`findtime`), per quanto tempo bannare (`bantime`)
3. **Action**: cosa fare quando il threshold viene superato - di default, aggiunge una regola `iptables -A INPUT -s <IP> -j REJECT`

### Installazione e abilitazione

```bash
sudo apt install fail2ban -y
sudo systemctl enable --now fail2ban
```

### Verifica dello stato della jail SSH

```bash
sudo fail2ban-client status sshd
```

Output atteso:

```
Status for the jail: sshd
|- Filter
|  |- Currently failed:	2
|  |- Total failed:	15
|  `- File list:	/var/log/auth.log
`- Actions
   |- Currently banned:	1
   |- Total banned:	3
   `- Banned IP list:	203.0.113.45
```

### Configurazione personalizzata (opzionale)

Per modificare i parametri della jail senza toccare il file di default (che viene sovrascritto dagli aggiornamenti):

```bash
sudo nano /etc/fail2ban/jail.local
```

```ini
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5       # Ban dopo 5 tentativi falliti
findtime = 600     # Finestra di 10 minuti
bantime = 3600     # Ban per 1 ora
```

> **Integrazione con Wazuh:** Fail2ban e Wazuh non sono in conflitto - si complementano. Fail2ban agisce (banna l'IP), Wazuh osserva e alerta (ti notifica dell'attacco). Wazuh legge i log di Fail2ban e genera alert quando un IP viene bannato, dandoti visibilita' centralizzata.

---

## 3. Firewall con UFW

**UFW (Uncomplicated Firewall)** e' un frontend per `iptables` (o `nftables` su Debian 12+) che semplifica la gestione delle regole di filtraggio del traffico di rete.

### Come funziona a basso livello: netfilter e iptables

UFW e' un'interfaccia semplificata per **iptables**, che a sua volta e' il frontend userspace di **netfilter** - il framework di packet filtering integrato nel kernel Linux. Per capire perche' l'ordine delle regole UFW conta (e debuggare quando qualcosa non funziona), serve capire l'architettura sottostante.

#### I 5 hook points di netfilter

Ogni pacchetto di rete che attraversa il kernel Linux passa attraverso una sequenza di **hook points** (punti di aggancio) dove le regole possono intercettarlo:

```
                                    Processo locale
                                    (SSH, Wazuh, Pi-hole)
                                         ▲    │
                                         │    │
                                      INPUT  OUTPUT
                                         │    │
Pacchetto ──► PREROUTING ──► Routing ──►─┘    └──► Routing ──► POSTROUTING ──► Uscita
in ingresso                  decision                decision                  rete
                                │                        ▲
                                │                        │
                                └────── FORWARD ─────────┘
                                   (pacchetti in transito,
                                    non destinati a questo host)
```

| Hook | Quando si attiva | Uso tipico |
|---|---|---|
| `PREROUTING` | Appena il pacchetto arriva, prima di qualsiasi decisione di routing | DNAT (port forwarding), modifica IP destinazione |
| `INPUT` | Dopo il routing, se il pacchetto e' destinato a un processo locale | **Firewall in ingresso** - dove UFW opera principalmente |
| `FORWARD` | Se il pacchetto deve essere inoltrato a un'altra interfaccia (il host fa da router) | Firewall per traffico in transito (es. container Docker) |
| `OUTPUT` | Generato da un processo locale, prima del routing in uscita | Firewall in uscita (raramente usato) |
| `POSTROUTING` | Dopo il routing, appena prima di uscire dall'interfaccia | SNAT/MASQUERADE (usato da WireGuard per il NAT dei client VPN) |

#### Le 4 tabelle di iptables

Le regole non sono tutte nello stesso "contenitore". iptables le organizza in **tabelle**, ognuna con uno scopo:

| Tabella | Scopo | Hook disponibili | Usata nel nostro progetto |
|---|---|---|---|
| `filter` | Accettare o scartare pacchetti (firewall) | INPUT, FORWARD, OUTPUT | **Si** - UFW, Fail2ban |
| `nat` | Modificare IP/porta sorgente o destinazione | PREROUTING, OUTPUT, POSTROUTING | **Si** - Docker bridge (NAT container), WireGuard (MASQUERADE) |
| `mangle` | Modificare header del pacchetto (TTL, TOS, marking) | Tutti e 5 | No (uso avanzato, QoS) |
| `raw` | Marcare pacchetti per bypassare connection tracking | PREROUTING, OUTPUT | No (uso avanzato) |

#### Connection Tracking (conntrack): firewall stateful

iptables (e quindi UFW) e' un **firewall stateful** - non valuta ogni pacchetto in isolamento, ma tiene traccia delle **connessioni**.

Verifica pratica - mostra le connessioni tracciate dal kernel:

```bash
sudo conntrack -L 2>/dev/null | head -5
# oppure
sudo cat /proc/net/nf_conntrack | head -5
```

Output esempio:

```
tcp  6 431999 ESTABLISHED src=192.168.0.50 dst=192.168.0.102 sport=54321 dport=22
     src=192.168.0.102 dst=192.168.0.50 sport=22 dport=54321 [ASSURED] use=1
```

Il kernel traccia lo **stato** di ogni connessione:

| Stato | Significato | Esempio |
|---|---|---|
| `NEW` | Primo pacchetto di una connessione mai vista | SYN TCP, prima query DNS UDP |
| `ESTABLISHED` | Pacchetto parte di una connessione gia' aperta | Pacchetti successivi al SYN-ACK |
| `RELATED` | Nuova connessione correlata a una esistente | Messaggio ICMP "port unreachable" in risposta a una connessione |
| `INVALID` | Pacchetto che non appartiene a nessuna connessione nota | Pacchetti malformati, scan TCP anomali |

**Perche' conta:** Quando UFW fa `default deny incoming`, in realta' blocca solo i pacchetti `NEW` in ingresso (nuove connessioni dall'esterno). I pacchetti `ESTABLISHED` e `RELATED` passano - altrimenti non potresti ricevere le risposte alle tue richieste (es. navigare web, fare apt update). Questo e' implementato dalla regola automatica:

```
-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

Puoi verificarlo:

```bash
sudo iptables -L ufw-before-input -n --line-numbers | head -10
```

#### Come UFW mappa su iptables: verifica pratica

Quando scrivi `sudo ufw allow ssh`, UFW genera:

```
-A ufw-user-input -p tcp --dport 22 -j ACCEPT
```

Per vedere **tutte** le regole iptables generate da UFW:

```bash
# Mostra la chain INPUT completa (incluse le chain di UFW)
sudo iptables -L INPUT -n --line-numbers

# Mostra le regole utente di UFW
sudo iptables -L ufw-user-input -n --line-numbers
```

L'ordine delle chain nella tabella `filter`:

```
Chain INPUT:
  1. ufw-before-logging-input   ← Log pre-regole
  2. ufw-before-input           ← Regole automatiche (conntrack ESTABLISHED, loopback)
  3. ufw-after-input             ← Regole automatiche post-utente
  4. ufw-after-logging-input     ← Log post-regole
  5. ufw-reject-input            ← Reject finale
  6. ufw-track-input             ← Tracking

Chain ufw-before-input (regole automatiche, NON modificabili da ufw):
  1. ACCEPT conntrack RELATED,ESTABLISHED  ← Risposte a connessioni gia' aperte
  2. ACCEPT loopback (127.0.0.1)           ← Traffico locale
  3. DROP conntrack INVALID                ← Pacchetti malformati
  4. → ufw-user-input                     ← Le TUE regole (ufw allow/deny)
```

Questo spiega perche' l'ordine delle regole UFW e' critico e perche' `ESTABLISHED` passa sempre: la regola conntrack e' **prima** delle regole utente nella chain.

### Configurazione base

```bash
sudo apt install ufw -y

# Policy di default: blocca tutto in ingresso, permetti tutto in uscita
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Permetti SSH (altrimenti ti chiudi fuori!)
sudo ufw allow ssh

# Attiva il firewall
sudo ufw enable
```

> **ATTENZIONE:** Esegui `sudo ufw allow ssh` PRIMA di `sudo ufw enable`. Se attivi il firewall senza permettere SSH, perderai l'accesso al Pi. L'unico modo per recuperare sara' collegare monitor e tastiera fisici, o riflashare la SD.

### Verifica

```bash
sudo ufw status verbose
```

Output atteso:

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere
```

### Regole aggiuntive per il progetto

Man mano che aggiungi servizi, dovrai aprire porte specifiche:

```bash
# Dashboard Wazuh (HTTPS)
sudo ufw allow from 192.168.0.0/24 to any port 443

# Portainer (HTTPS)
sudo ufw allow from 192.168.0.0/24 to any port 9443

# Wazuh Agent communication
sudo ufw allow from 192.168.0.0/24 to any port 1514 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 1515 proto tcp

# Honeypot (aperto a tutti - deve essere raggiungibile dagli attaccanti)
sudo ufw allow 2222/tcp
```

> **Principio del minimo privilegio:** Apri solo le porte che servono, solo dagli IP che devono accedervi. Le porte di gestione (SSH, Portainer, Wazuh Dashboard) vanno limitate alla rete locale (`192.168.0.0/24`). Solo i servizi che devono essere esposti a Internet (Honeypot, VPN) vanno aperti a tutti.

---

## 3.1 Kernel Hardening con sysctl

Oltre al firewall, il kernel Linux espone parametri configurabili via `sysctl` che rafforzano il network stack e la memoria. Questi parametri sono particolarmente importanti per un sistema esposto su Internet (anche indirettamente tramite honeypot).

### Configurazione

Creare il file `/etc/sysctl.d/99-hardening.conf`:

```bash
sudo nano /etc/sysctl.d/99-hardening.conf
```

```ini
# === NETWORK STACK HARDENING ===

# Abilita protezione SYN flood (SYN cookies)
# Quando la coda SYN e' piena, il kernel genera un SYN cookie crittografico
# invece di allocare memoria - previene DoS da SYN flood
net.ipv4.tcp_syncookies = 1

# Disabilita il source routing
# Il source routing permette al mittente di specificare il percorso dei pacchetti
# attraverso la rete - usato in attacchi di routing manipulation
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Ignora ICMP redirect
# I redirect ICMP dicono all'host di usare un gateway diverso
# Un attaccante puo' usarli per redirigere il traffico (MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Disabilita invio di ICMP redirect
# Un server non dovrebbe mai agire da router - non invia redirect
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Abilita Reverse Path Filtering (anti-spoofing)
# Il kernel verifica che l'IP sorgente di un pacchetto in ingresso sia
# raggiungibile dall'interfaccia su cui e' arrivato - blocca pacchetti con
# IP sorgente falsificato
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignora ping broadcast (prevenzione Smurf attack)
# Un attaccante invia ping all'indirizzo broadcast della rete con IP sorgente
# falsificato (la vittima) - tutti gli host rispondono alla vittima
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log dei pacchetti "marziani" (IP sorgente impossibile)
# Utile per debug e per rilevare tentativi di spoofing
net.ipv4.conf.all.log_martians = 1

# === MEMORY PROTECTION ===

# ASLR (Address Space Layout Randomization) - livello massimo
# Randomizza le posizioni di stack, heap, mmap e librerie in memoria
# Rende molto piu' difficile sfruttare vulnerabilita' di buffer overflow
# 0 = disabilitato, 1 = stack/mmap, 2 = stack/mmap/heap (massimo)
kernel.randomize_va_space = 2

# Proteggi i symlink e hardlink in directory world-writable (/tmp)
# Previene attacchi di symlink race condition (privilege escalation)
fs.protected_symlinks = 1
fs.protected_hardlinks = 1

# Limita l'accesso a dmesg a utenti con CAP_SYSLOG
# dmesg puo' rivelare informazioni sulla memoria del kernel (utili per exploit)
kernel.dmesg_restrict = 1

# Disabilita la possibilita' di caricare moduli kernel non firmati
# Previene il caricamento di rootkit come moduli kernel
# NOTA: abilitare solo se tutti i moduli necessari sono gia' caricati
# kernel.modules_disabled = 1   # <-- COMMENTATO: WireGuard potrebbe aver bisogno di caricare moduli

# Limita l'uso di perf (performance counters) - usabili per side-channel attacks
kernel.perf_event_paranoid = 3
```

### Applicare le modifiche

```bash
sudo sysctl --system
```

### Verifica

```bash
# Controlla che i parametri siano attivi
sysctl net.ipv4.tcp_syncookies
# net.ipv4.tcp_syncookies = 1

sysctl kernel.randomize_va_space
# kernel.randomize_va_space = 2
```

> **Nota su `kernel.modules_disabled`:** Se lo abiliti (valore 1), nessun modulo kernel potra' piu' essere caricato fino al prossimo reboot. Questo blocca i rootkit kernel-mode, ma impedisce anche a WireGuard di caricare il suo modulo se non e' gia' caricato. Abilitare solo dopo aver verificato che tutti i servizi funzionano correttamente.

---

## 4. Aggiornamenti Automatici

Le vulnerabilita' vengono scoperte quotidianamente. Un sistema non aggiornato e' un bersaglio facile. `unattended-upgrades` installa automaticamente le patch di sicurezza senza intervento manuale.

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure unattended-upgrades
```

Il comando `dpkg-reconfigure` mostra una schermata interattiva - selezionare **Yes** per abilitare gli aggiornamenti automatici.

**Cosa viene aggiornato automaticamente:**

- Patch di sicurezza Debian (repository `*-security`)
- **NON** aggiornamenti di funzionalita' o nuove versioni major

Questo e' il comportamento corretto per un server: vuoi le fix di sicurezza, non vuoi che un aggiornamento ti rompa OMV o Docker senza preavviso.

---

## 5. Verifica integrazione Wazuh (EXTRA)

Se Wazuh e' installato (vedi sezione SOC Analyst/Wazuh), possiamo verificare che il modulo **Syscheck (File Integrity Monitoring)** stia monitorando il sistema.

### Cos'e' il File Integrity Monitoring (FIM)

FIM calcola l'hash crittografico (SHA-256) di ogni file nelle directory monitorate (es. `/etc`, `/usr/bin`). Periodicamente, ricalcola gli hash e confronta. Se un file e' stato modificato, creato o eliminato, Wazuh genera un alert.

**Perche' e' critico:** Se un attaccante modifica `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config` o un binario di sistema, Wazuh lo rileva. Questo e' fondamentale per individuare compromissioni post-exploitation.

### Verifica che Syscheck sia attivo

```bash
sudo /var/ossec/bin/wazuh-control status
```

Cercare: `wazuh-syscheckd is running`

### Controllare i log di Syscheck

```bash
sudo tail -f /var/ossec/logs/ossec.log
```

Cercare righe come:

```
wazuh-syscheckd: INFO: Monitoring directory: '/etc'
wazuh-syscheckd: INFO: Monitoring directory: '/usr/bin'
```

### Test pratico - generare un alert FIM

```bash
# Crea un file in una directory monitorata
sudo touch /etc/test-wazuh

# Osserva i log
sudo tail -f /var/ossec/logs/ossec.log
```

Entro pochi minuti (dipende dall'intervallo di scan configurato), vedrai un evento FIM nei log. L'alert comparira' anche nella Dashboard Wazuh sotto **Security Events**.

```bash
# Pulizia dopo il test
sudo rm /etc/test-wazuh
```

### Forzare un rescan immediato

```bash
sudo /var/ossec/bin/wazuh-control restart
```

Questo forza:

- Nuovo scan completo del filesystem
- Ricalcolo di tutti gli hash
- Invio degli eventi al Manager

---

## Osservazioni finali

Con queste misure attive, il sistema ha ora:

| Layer | Protezione | Cosa rileva/blocca |
|---|---|---|
| **SSH** | Chiave pubblica, no root, no password | Brute force, accesso non autorizzato |
| **Fail2ban** | Ban automatico IP | Bot e scanner automatici |
| **UFW** | Firewall con policy deny-by-default | Scansioni di porta, accessi non autorizzati |
| **Unattended Upgrades** | Patch automatiche | Vulnerabilita' note (CVE) |
| **Wazuh FIM** | Integrity monitoring | Modifiche non autorizzate ai file di sistema |

Wazuh iniziera' a generare alert per:

- Tentativi SSH falliti (rule.id: 5710, 5712)
- Ban di Fail2ban (rule.id: 87101-87105)
- Modifiche a file monitorati (rule.id: 550-554)
- Escalation di privilegi (`sudo` usage - rule.id: 5401-5405)

---

Prossimo step: [VLAN (Virtual LAN)](../VLAN%20(Virtual%20LAN)/) - segmentazione di rete avanzata, oppure [VPN](../VPN%20(Virtual%20Private%20Network)/) - accesso remoto sicuro.
