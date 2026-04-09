# Deep Dive: il protocollo SSH dalla connessione TCP all'autenticazione

Per capire le direttive di `sshd_config`, bisogna prima capire cosa succede quando digiti `ssh pi@192.168.0.102`. Il protocollo SSH (RFC 4251-4254) si articola in 5 fasi sequenziali:

```
Client (il tuo PC)                                     Server (Raspberry Pi)
       |                                                       |
       |---- [FASE 1] TCP Handshake (porta 22) -------------->|
       |     SYN -> SYN-ACK -> ACK                            |
       |                                                       |
       |---- [FASE 2] Version Exchange ----------------------->|
       |     "SSH-2.0-OpenSSH_9.7"                             |
       |<--- "SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3" --------|
       |                                                       |
       |---- [FASE 3] Key Exchange (KEX) --------------------->|
       |     Lista algoritmi supportati (KEX, cifratura,       |
       |     MAC, compressione) -> negoziazione                |
       |                                                       |
       |     Diffie-Hellman (curve25519-sha256):               |
       |     Client genera e_c (effimera), invia Q_c = e_c*G  |
       |<--- Server genera e_s, invia Q_s = e_s*G + host_key -|
       |                                                       |
       |     Entrambi calcolano: K = e_c * Q_s = e_s * Q_c    |
       |     (shared secret identico, mai trasmesso)           |
       |                                                       |
       |     H = hash(V_c, V_s, I_c, I_s, K_s, Q_c, Q_s, K)  |
       |     Il server FIRMA H con la sua host key privata     |
       |     e invia la firma al client                        |
       |                                                       |
       |     -> Session keys derivate da K e H tramite SHA-256 |
       |     -> Da questo momento TUTTO il traffico e' cifrato |
       |                                                       |
       |---- [FASE 4] Canale cifrato stabilito --------------->|
       |     NEWKEYS -> entrambi i lati switchano alle nuove   |
       |     chiavi di sessione                                |
       |                                                       |
       |---- [FASE 5] User Authentication -------------------->|
       |     (vedi sotto: password o chiave pubblica)          |
       |                                                       |
```

---

## Fase 2: Version Exchange

I primi byte scambiati su una connessione SSH sono **testo in chiaro** - non ancora cifrati. Entrambi i lati inviano la stringa di versione nel formato `SSH-protoversion-softwareversion`:

```
SSH-2.0-OpenSSH_8.4p1 Debian-5+deb11u3
|    |   |              |
|    |   |              +-- Patch del pacchetto Debian
|    |   +-- Software e versione (information disclosure!)
|    +-- Versione del protocollo (2.0)
+-- Identificatore del protocollo
```

> **Implicazione di sicurezza:** Questa stringa e' visibile a chiunque si connetta alla porta 22. Rivela il software, la versione, e il sistema operativo. Un attaccante usa queste informazioni per cercare CVE specifiche. Per questo Cowrie emula una versione diversa (`OpenSSH_6.0p1`) - per sembrare un bersaglio appetibile.

---

## Fase 3: Key Exchange (Diffie-Hellman su Curve25519)

Questa e' la fase piu' critica. Il client e il server devono concordare una **chiave segreta condivisa** senza mai trasmetterla sulla rete. Usano il protocollo Diffie-Hellman sulla curva ellittica Curve25519:

**La matematica (semplificata):**

1. Entrambi conoscono una curva ellittica `E` e un punto generatore `G` (parametri pubblici di Curve25519)
2. Il **client** genera un numero casuale `e_c` (chiave effimera privata) e calcola `Q_c = e_c * G` (moltiplicazione scalare sul punto della curva). Invia `Q_c` al server
3. Il **server** genera `e_s` e calcola `Q_s = e_s * G`. Invia `Q_s` al client
4. Il **client** calcola `K = e_c * Q_s = e_c * e_s * G`
5. Il **server** calcola `K = e_s * Q_c = e_s * e_c * G`
6. `K` e' identico su entrambi i lati (proprieta' commutativa della moltiplicazione scalare), ma **non e' mai transitato sulla rete**

Un attaccante che intercetta `Q_c` e `Q_s` dovrebbe risolvere il **Problema del Logaritmo Discreto su Curva Ellittica (ECDLP)** per ricavare `e_c` o `e_s` - computazionalmente impossibile con le dimensioni di Curve25519 (256 bit -> sicurezza ~128 bit).

**Session Key derivation:** Dal segreto condiviso `K` e dall'hash di sessione `H`, SSH deriva 6 chiavi separate usando SHA-256:

| Chiave | Scopo |
|---|---|
| `IV_c->s` | Initialization Vector per cifratura client -> server |
| `IV_s->c` | Initialization Vector per cifratura server -> client |
| `Enc_c->s` | Chiave di cifratura client -> server (ChaCha20 o AES-256) |
| `Enc_s->c` | Chiave di cifratura server -> client |
| `MAC_c->s` | Chiave HMAC per integrita' client -> server |
| `MAC_s->c` | Chiave HMAC per integrita' server -> client |

Chiavi separate per ogni direzione prevengono attacchi di reflection (un attaccante che reinvia pacchetti del client al client stesso).

---

## Host Keys vs User Keys: la distinzione fondamentale

SSH usa **due tipi di chiavi asimmetriche** per scopi completamente diversi. Confonderli e' un errore comune.

### Host Keys (chiavi del server)

```
/etc/ssh/ssh_host_ed25519_key       <-- Chiave PRIVATA del server (permessi 600)
/etc/ssh/ssh_host_ed25519_key.pub   <-- Chiave PUBBLICA del server
/etc/ssh/ssh_host_rsa_key           <-- Stessa cosa, algoritmo RSA
/etc/ssh/ssh_host_ecdsa_key         <-- Stessa cosa, algoritmo ECDSA
```

- **Generate automaticamente** al primo avvio di `sshd` (o durante l'installazione dell'OS)
- Servono ad **autenticare il server al client** - "sei davvero il mio Raspberry Pi, o un impostore?"
- Il server firma l'hash di sessione `H` con la host key privata durante il KEX (Fase 3)
- Il client verifica la firma usando la host key pubblica salvata in `~/.ssh/known_hosts`
- **Se cambiano** (reinstallazione OS, diverso dispositivo sullo stesso IP): l'avviso "REMOTE HOST IDENTIFICATION HAS CHANGED"

### User Keys (chiavi dell'utente)

```
~/.ssh/id_ed25519       <-- Chiave PRIVATA dell'utente (protetta da passphrase)
~/.ssh/id_ed25519.pub   <-- Chiave PUBBLICA dell'utente (copiata sul server)
```

- **Generate dall'utente** con `ssh-keygen`
- Servono ad **autenticare l'utente al server** - "sei davvero Nick, o un impostore?"
- La chiave pubblica viene copiata in `~/.ssh/authorized_keys` sul server
- La chiave privata **non lascia mai il client**

---

## Il Fingerprint: cos'e', come si genera, come si verifica

Quando ti connetti a un server SSH per la prima volta:

```
The authenticity of host '192.168.0.102 (192.168.0.102)' can't be established.
ED25519 key fingerprint is SHA256:xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0=.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Cos'e' il fingerprint:**

```
Chiave pubblica del server (Ed25519, 256 bit)
    |
    v SHA-256 hash
[32 byte di hash]
    |
    v Base64 encode
"xK7vN2mP9qR8sT1uV3wX5yZ7aB9cD2eF4gH6iJ8kL0="
    |
    v Prefisso algoritmo
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

---

## Il file `known_hosts`: la Trust-On-First-Use (TOFU) database

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
3. **Match** -> connessione procede silenziosamente
4. **Mismatch** -> "REMOTE HOST IDENTIFICATION HAS CHANGED" (possibile MitM)
5. **Non trovato** -> chiede di accettare il fingerprint (prima connessione)

Questo modello si chiama **TOFU (Trust-On-First-Use)**: ti fidi della prima connessione e verifichi che le successive siano coerenti. E' piu' debole di una PKI (dove un'autorita' certifica l'identita'), ma piu' pratico per SSH.

---

## Il file `authorized_keys`: formato e meccanismo

Sul server, `~/.ssh/authorized_keys` contiene le chiavi pubbliche degli utenti autorizzati:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx nick@homelab
|            |                                                                    |
|            +-- Chiave pubblica (Base64)                                         +-- Commento (opzionale)
+-- Tipo di chiave
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

---

## Autenticazione con chiave pubblica: il challenge-response

Quando `PasswordAuthentication no` e `PubkeyAuthentication yes`, ecco cosa succede nella Fase 5:

```
Client                                              Server
   |                                                    |
   |-- "Voglio autenticarmi come pi                     |
   |    con chiave ssh-ed25519 AAAA..."  -------------->|
   |                                                    |
   |    Il server cerca AAAA... in                      |
   |    ~pi/.ssh/authorized_keys                        |
   |                                                    |
   |    Se trovata:                                     |
   |<-- Challenge: dati random cifrati  ----------------|
   |    con la chiave pubblica del client               |
   |                                                    |
   |    Il client FIRMA il challenge                    |
   |    con la sua chiave PRIVATA                       |
   |    (la chiave privata non viene MAI inviata)       |
   |                                                    |
   |-- Signature(challenge, private_key)  ------------->|
   |                                                    |
   |    Il server VERIFICA la firma                     |
   |    usando la chiave pubblica                       |
   |    in authorized_keys                              |
   |                                                    |
   |    Firma valida?                                   |
   |    SI -> accesso consentito                        |
   |    NO -> accesso negato                            |
   |                                                    |
   |<-- SSH_MSG_USERAUTH_SUCCESS  ----------------------|
```

**Il punto cruciale:** la chiave privata non attraversa mai la rete. Il server invia una sfida (challenge), il client la firma con la chiave privata, il server verifica la firma con la chiave pubblica. Questo e' il principio fondamentale della crittografia asimmetrica applicata all'autenticazione: **la conoscenza della chiave pubblica permette di verificare, ma non di forgiare, una firma**.

Anche se un attaccante intercettasse l'intera sessione, otterrebbe solo la firma di quel challenge specifico - non la chiave privata, e non una firma riutilizzabile (ogni challenge e' unico).
