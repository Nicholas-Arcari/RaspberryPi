>  [English](integrita-post-downtime.en.md) |  **Italiano**

# Runbook 06 - Integrita' post-downtime

> **Quando usare questo runbook:** il sistema e' stato spento, irraggiungibile o fuori dal tuo controllo per un periodo (una vacanza, un blackout, un guasto) e vuoi verificare, prima di rifidarti di lui, che **nessuno sia entrato, nulla sia stato manomesso e non ci sia un man-in-the-middle** sulla rete. E' il runbook di incident response applicato al "non so cosa e' successo mentre non guardavo".

Principio guida: **assume breach, poi smentiscilo con le prove.** Non parti da "probabilmente e' tutto ok"; parti da "cosa mi dimostra che e' tutto ok?". Se non hai una baseline (Regola d'oro n.2 del [README](../README.md)), molti di questi controlli perdono forza: e' il motivo per cui la baseline si cattura da sani.

> **Ordine importante:** se in QUALSIASI punto trovi un indicatore forte di compromissione, **fermati e isola** prima di continuare a "sistemare" (stacca la rete, non spegnere - la RAM e' evidenza). Vedi la sezione Contenimento in fondo.

---

## Fase 1 - Chi e' entrato, e quando

```bash
# Ultimi accessi riusciti (utenti, IP, orari). Cerca sessioni nel periodo di downtime.
last -aiF | head -30
# Righe con IP sconosciuti o orari in cui il sistema doveva essere spento <-- SOSPETTO

# Ultimi accessi FALLITi (brute force)
sudo lastb -aiF | head -30

# Accessi SSH accettati nel periodo (chi, da dove, con quale metodo)
sudo journalctl -u ssh --since "2026-08-01" --until "2026-08-17" | grep -i "Accepted"
# Atteso: solo i tuoi accessi, dai tuoi IP, "Accepted publickey"
# "Accepted password" <-- allarme: la password auth dovrebbe essere disabilitata

# Sessioni attive adesso (c'e' qualcuno oltre te?)
who -a
w
```

## Fase 2 - Utenti, chiavi e privilegi: sono cambiati?

Un attaccante che entra crea persistenza: un nuovo utente, una nuova chiave SSH, un sudo.

```bash
# Nuovi utenti con shell di login o UID 0 (backdoor classica)
awk -F: '($3>=1000 || $3==0) && $7 !~ /nologin|false/ {print $1, $3, $7}' /etc/passwd
# Atteso: solo i tuoi utenti. Un secondo UID 0 = backdoor grave

# Chiavi SSH autorizzate: qualcuna che non hai messo tu?
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys \
         /var/lib/openmediavault/ssh/authorized_keys/*; do
  [ -f "$f" ] && echo "== $f ==" && cat "$f"
done
# Confronta OGNI chiave con le tue note. Una chiave sconosciuta = accesso persistente altrui

# Modifiche recenti a file sensibili di auth (mtime nel periodo di downtime)
sudo ls -la --time-style=full-iso /etc/passwd /etc/shadow /etc/sudoers
sudo find /etc/sudoers.d -type f -newermt "2026-08-01" -ls
```

## Fase 3 - Persistenza: cron, servizi, avvio

```bash
# Cron di tutti gli utenti + cron di sistema modificati di recente
for u in $(cut -f1 -d: /etc/passwd); do crontab -l -u "$u" 2>/dev/null | sed "s/^/[$u] /"; done
sudo find /etc/cron* /var/spool/cron -type f -newermt "2026-08-01" -ls

# Servizi systemd creati/modificati di recente (persistenza moderna)
sudo find /etc/systemd/system /lib/systemd/system -name "*.service" -newermt "2026-08-01" -ls
systemctl list-unit-files --state=enabled | grep -vE "$(known good...)"   # confronta con baseline

# Cerca abilitazioni sospette all'avvio
grep -R "" /etc/rc.local 2>/dev/null
```

## Fase 4 - Integrita' dei file: FIM e pacchetti

Qui la baseline paga. Wazuh FIM ha registrato ogni modifica ai file monitorati: interrogalo per il periodo.

```bash
# Modifiche rilevate dal FIM nel periodo (dalla dashboard Wazuh: modulo Integrity Monitoring)
# Da CLI, gli alert syscheck registrati:
sudo grep -i syscheck /var/ossec/logs/alerts/alerts.json | \
  grep -E "2026-08-(0[1-9]|1[0-7])" | tail -50
# Ogni modifica a /etc, ai binari, alle config va giustificata da una TUA azione

# Integrita' dei pacchetti installati (i binari di sistema sono quelli originali?)
sudo apt install -y debsums >/dev/null 2>&1
sudo debsums -c 2>/dev/null
# Atteso: nessun output. Ogni file elencato = binario modificato rispetto al pacchetto <-- grave

# Rootkit/backdoor noti
sudo apt install -y rkhunter chkrootkit >/dev/null 2>&1
sudo rkhunter --check --sk --report-warnings-only
sudo chkrootkit -q
```

## Fase 5 - Superficie di rete: cosa e' in ascolto adesso?

```bash
# Porte in ascolto e processo relativo: confronta con la baseline (Runbook 08)
sudo ss -tulnp
# Una porta/servizio nuovo che non hai messo tu = possibile impianto (reverse shell, C2)

# Connessioni in uscita stabilite (un impianto "telefona a casa")
sudo ss -tunp state established
# IP di destinazione sconosciuti, ripetuti, verso porte strane <-- indagare (beaconing)
```

---

## Fase 6 - Man-in-the-middle sulla LAN

Questa e' la parte specifica della domanda "qualcuno si e' messo come man-in-the-middle?". Un MITM su LAN si fa quasi sempre con **ARP spoofing** (l'attaccante convince i dispositivi che il suo MAC e' quello del gateway) o con un **rogue DHCP/DNS** (distribuisce se' stesso come gateway o resolver).

### 6.1 Verifica il MAC del gateway (anti ARP-spoofing)

```bash
# Chi dice di essere il gateway 192.168.0.1, e con quale MAC?
ip neigh show 192.168.0.1
# Confronta il MAC con quello REALE del router (letto una volta, da sano, e annotato nella baseline).
# MAC diverso dal previsto = qualcuno sta impersonando il gateway <-- MITM

# La tabella ARP intera: due IP con lo stesso MAC, o il MAC del gateway associato a piu' IP?
ip neigh show
arp -an
# Anomalie classiche di ARP spoofing:
#  - il MAC del gateway compare anche su un altro IP
#  - un IP "flappa" tra due MAC diversi
```

### 6.2 Rogue DHCP: c'e' un secondo server DHCP?

```bash
# Sonda i server DHCP presenti sulla LAN (dovrebbe rispondere SOLO il router)
sudo apt install -y dhcpdump isc-dhcp-client >/dev/null 2>&1
sudo nmap --script broadcast-dhcp-discover 2>/dev/null | grep -E "Server Identifier|Router|DNS"
# Atteso: un solo Server Identifier = 192.168.0.1
# Due risposte / un server diverso <-- rogue DHCP: qualcuno vuole diventare il tuo gateway/DNS
```

### 6.3 DNS: sto usando il resolver giusto?

```bash
# Il DNS effettivo e' il Pi-hole previsto?
resolvectl status | grep "DNS Servers" || cat /etc/resolv.conf
# Un DNS diverso da 192.168.0.250 che non hai impostato tu <-- DNS hijacking

# Il gateway effettivo e' quello giusto?
ip route | grep default
# default via un IP diverso da 192.168.0.1 <-- rotta dirottata
```

### 6.4 Certificati e known_hosts (MITM su TLS/SSH)

Un MITM attivo su TLS/SSH cambia le impronte crittografiche: e' il segnale piu' affidabile.

```bash
# La fingerprint host SSH del Pi e' ancora quella che conosci?
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# Confronta con la fingerprint annotata nella baseline. Diversa = chiave host cambiata
# (o reinstallazione, o MITM). I client che ricevono un "host key changed" NON devono ignorarlo.

# Dai client: un warning "REMOTE HOST IDENTIFICATION HAS CHANGED" verso il Pi
# e' esattamente il sintomo di MITM SSH e non va mai bypassato con leggerezza.
```

---

## Contenimento: cosa fare se trovi qualcosa

Se una qualsiasi fase mostra un indicatore forte (utente sconosciuto, chiave estranea, binario modificato, MAC del gateway spoofato):

1. **Isola, non spegnere.** Stacca il cavo di rete (o blocca tutto con `ufw default deny`). Non spegnere: la RAM e i processi vivi sono evidenza. Se devi scegliere, isola dalla rete.
2. **Non "pulire" subito.** Cancellare la backdoor distrugge le prove per capire come e' entrato. Prima documenta (screenshot, copia dei log, `ss`, `ps auxf`, tabella ARP).
3. **Raccogli l'evidenza volatile:** `ps auxf`, `ss -tunp`, `who`, `last`, `ip neigh`, `docker ps`, copia di `/var/ossec/logs/` e `/var/log/`.
4. **Determina il blast radius:** l'accesso era solo al Pi o anche ad altri host? Le credenziali su di esso (chiavi WireGuard, password Wazuh, SMB) vanno considerate compromesse e ruotate.
5. **Ripristina da uno stato fidato:** in caso di compromissione confermata dei binari, la strada pulita e' reinstallare da zero e ripristinare **solo i dati** (non i binari) dai backup -> [Runbook 08](backup-e-disaster-recovery.md). Ruota tutte le credenziali e le chiavi.

---

## Prevenzione (perche' questi controlli funzionino)

- **Cattura la baseline da sani** (Regola d'oro n.2): MAC reale del gateway, fingerprint host SSH, elenco porte in ascolto, hash dei binari critici, elenco utenti e chiavi. Senza baseline, "e' cambiato?" non ha risposta.
- Tieni il **FIM di Wazuh in realtime** su `/etc`, `/root`, i binari e gli `authorized_keys`: e' il registratore che rende questa indagine possibile a posteriori.
- Abilita **static ARP** per il gateway sui client critici, o una funzione di **ARP inspection** sullo switch gestito, per rendere l'ARP spoofing molto piu' difficile.
- Fai in modo che Wazuh **allerti in tempo reale** su: nuovo utente, nuova chiave SSH, `Accepted password` su SSH, modifica di `/etc/sudoers`. Cosi' non devi aspettare un downtime per accorgertene.

---

## Collegamenti

- Provare che le difese (incluso il FIM) funzionino -> [Runbook 05: verifica difese attive](verifica-difese-attive.md)
- Health check di rete completo (rogue DHCP, ARP, VLAN) -> [Runbook 07: LAN health check](lan-health-check.md)
- Ripristino pulito da backup dopo compromissione -> [Runbook 08: backup e disaster recovery](backup-e-disaster-recovery.md)
- Incident response strutturata (fasi NIST) -> [SOC Analyst / incident-response](../../SOC%20Analyst/docs/incident-response.md)
