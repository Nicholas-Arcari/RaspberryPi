# Primo Accesso e Aggiornamento del Sistema

## Step 2: Primo Accesso via SSH

Inserire la MicroSD nel Raspberry Pi, collegare il cavo Ethernet e l'alimentazione. Attendere ~60 secondi per il primo boot (il primo avvio e' piu' lento perche' espande il filesystem e applica le customizzazioni).

### Individuare l'IP del Raspberry

Se non conosci l'IP assegnato dal DHCP:

```bash
# Dal router: controllare la tabella DHCP clients
# Oppure, da un altro PC sulla stessa rete:
nmap -sn 192.168.0.0/24
# Oppure, su Windows:
arp -a
```

### Connessione SSH

```bash
ssh pi@<IP_DEL_RASPBERRY>
```

Al primo collegamento, SSH chiedera' di confermare il fingerprint del server:

```
The authenticity of host '192.168.0.102 (192.168.0.102)' can't be established.
ED25519 key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**Cosa sta succedendo a livello tecnico:** SSH utilizza il protocollo di scambio chiavi Diffie-Hellman (o la variante ECDH con Curve25519) per stabilire una sessione cifrata. La prima volta che ti connetti, il client non ha mai visto quel server e ti chiede di verificare manualmente il fingerprint - una rappresentazione compressa della chiave pubblica del server (nel formato `SHA256:base64`). Digitando `yes`, il client salva questa associazione `IP → chiave pubblica` nel file `~/.ssh/known_hosts`.

### Il temuto "REMOTE HOST IDENTIFICATION HAS CHANGED"

Se dopo una reinstallazione dell'OS, una reflash della SD o un cambio di dispositivo sullo stesso IP, SSH mostrera':

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
```

**Cosa sta succedendo:** SSH ha confrontato la chiave pubblica presentata dal server con quella salvata in `known_hosts` e ha trovato una discrepanza. Questo e' esattamente il meccanismo che protegge da un attacco **Man-in-the-Middle (MitM)**: se un attaccante si interponesse tra te e il server, presenterebbe una chiave diversa e SSH bloccherebbe la connessione.

Nel nostro caso, sappiamo che il cambio di chiave e' legittimo (abbiamo reinstallato l'OS), quindi possiamo rimuovere la vecchia entry:

```bash
ssh-keygen -R <IP_DEL_RASPBERRY>
```

Questo comando rimuove la riga corrispondente a quell'IP dal file `~/.ssh/known_hosts`. La prossima connessione chiedera' di nuovo di accettare il nuovo fingerprint.

> **Attenzione:** Se non hai reinstallato nulla e vedi questo avviso, **fermati e indaga**. Potrebbe essere un vero attacco MitM, un ARP spoofing sulla rete locale, o un altro dispositivo che ha preso lo stesso IP.

---

## Step 3: Aggiornamento del sistema

Dopo il primo accesso, aggiornare immediatamente tutti i pacchetti:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

**Perche' `full-upgrade` e non `upgrade`:**

- `apt upgrade`: aggiorna solo i pacchetti che non richiedono la rimozione o l'installazione di nuovi pacchetti
- `apt full-upgrade`: aggiorna tutto, anche se richiede di rimuovere pacchetti obsoleti o installarne di nuovi (necessario per aggiornamenti del kernel e delle librerie di sistema)

Su un sistema appena installato, `full-upgrade` garantisce di avere tutte le patch di sicurezza piu' recenti, incluse quelle del kernel.
