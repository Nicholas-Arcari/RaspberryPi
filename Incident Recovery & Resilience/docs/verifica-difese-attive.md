>  [English](verifica-difese-attive.en.md) |  **Italiano**

# Runbook 05 - Verifica delle difese attive

> **Quando usare questo runbook:** vuoi essere sicuro che firewall, Fail2ban, hardening SSH, Wazuh FIM, honeypot e segmentazione **funzionino ancora davvero** - non solo che i servizi risultino "attivi". Da eseguire dopo ogni aggiornamento importante, dopo un ripristino, o periodicamente come drill.

La differenza chiave rispetto alla [checklist post-installazione](../../docs/checklist-post-installazione.md): quella verifica che le difese siano **su** (controllo positivo di stato). Questo runbook verifica che **facciano il loro lavoro** (controllo di efficacia), provando attivamente a farle scattare. E' l'approccio "verifica, non fidarti": un servizio `active` che non blocca nulla e' peggio di un servizio spento, perche' ti da' un falso senso di sicurezza.

> **Nota etica e di sicurezza:** tutti i test seguenti sono da eseguire **solo sul tuo lab**, dispositivi di tua proprieta'. Sono verifiche difensive (control validation), la versione casalinga di un purple team. Non puntarli mai su reti o sistemi di terzi.

---

## 1. Firewall (UFW): blocca davvero?

Non basta `ufw status: active`. Va provato che una porta chiusa sia effettivamente irraggiungibile e una aperta no, **da un altro host** della LAN (non da localhost, che bypassa molte regole).

```bash
# Da un secondo dispositivo (es. il tuo PC), scansiona il Pi
nmap -Pn -p 22,80,443,53,9443,12345 192.168.0.102
# Atteso: aperte solo le porte previste (es. 22, 443...).
# Una porta che dovrebbe essere chiusa e risulta "open" <-- FALLA nel firewall
# La 12345 (inventata) DEVE risultare filtered/closed -> conferma il default-deny
```

```bash
# Sul Pi: le regole sono quelle che credi?
sudo ufw status numbered
# Confronta con la baseline salvata (Runbook 08). Regole in piu' = deriva di configurazione
```

## 2. Fail2ban: banna davvero?

L'unico modo per esserne certi e' **farlo scattare** con tentativi falliti controllati.

```bash
# Da un host di test (NON il tuo IP in ignoreip), genera login SSH falliti:
for i in $(seq 1 6); do ssh -o BatchMode=yes -o ConnectTimeout=3 baduser@192.168.0.102 true 2>/dev/null; done

# Sul Pi: l'IP di test e' finito in ban?
sudo fail2ban-client status sshd
# Atteso: "Banned IP list:" contiene l'IP di test  <-- Fail2ban funziona

# Pulisci dopo il test
sudo fail2ban-client set sshd unbanip <IP_DI_TEST>
```

Se il ban non scatta: controlla che la jail `sshd` sia `enabled`, che `logpath` punti al log giusto (`/var/log/auth.log`) e che il `maxretry` sia coerente.

## 3. Hardening SSH: le direttive reggono?

```bash
# Password auth deve essere RIFIUTATA (accetta solo chiavi)
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no pi@192.168.0.102
# Atteso: "Permission denied (publickey)" -> password disabilitata come deve

# Root login deve essere rifiutato
ssh root@192.168.0.102
# Atteso: rifiuto -> PermitRootLogin no funziona

# La config effettiva (non quella che credi di aver scritto)
sudo sshd -T | grep -Ei "permitrootlogin|passwordauthentication|pubkeyauthentication"
# Atteso: permitrootlogin no / passwordauthentication no / pubkeyauthentication yes
```

## 4. Kernel hardening: i sysctl sono applicati?

```bash
sudo sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space net.ipv4.conf.all.rp_filter
# Atteso: tcp_syncookies = 1, randomize_va_space = 2, rp_filter = 1
# Se un valore e' tornato a default dopo un update -> il file in /etc/sysctl.d/ non e' applicato
```

## 5. Wazuh FIM: rileva la modifica di un file critico?

Questo e' il test piu' importante, perche' il FIM (File Integrity Monitoring) e' cio' su cui si basa il [Runbook 06](integrita-post-downtime.md) per rilevare le manomissioni. Va provato che scatti davvero.

```bash
# Crea/modifica un file in una directory monitorata (es. /etc)
sudo touch /etc/test-fim-$(date +%s).conf

# Attendi il ciclo di scan (o forzalo) e cerca l'alert
# Sul Pi (o nella dashboard): syscheck deve generare un evento
sudo tail -n 50 /var/ossec/logs/alerts/alerts.json | grep -i syscheck
# Atteso: un alert con "path" del file appena creato e regola FIM (rule id 550/554...)
# Pulisci:
sudo rm /etc/test-fim-*.conf
```

Se non scatta: verifica che `/etc` sia in `<syscheck>` in `ossec.conf`, e che il FIM sia in modalita' realtime o che sia passato un ciclo di scan.

## 6. Detection: le regole reagiscono a un evento?

```bash
# Genera un evento che deve produrre un alert (es. sudo fallito)
sudo -k ; sudo -S true <<< "password-sbagliata" 2>/dev/null

# Cerca l'alert corrispondente
sudo tail -n 100 /var/ossec/logs/alerts/alerts.json | grep -i "authentication\|sudo"
# Atteso: alert di autenticazione fallita. Assenza -> decoder/regole non attive
```

## 7. Honeypot (Cowrie): cattura e inoltra a Wazuh?

```bash
# Simula un attaccante che entra nel honeypot (dal tuo PC)
ssh -o StrictHostKeyChecking=no root@192.168.0.102 -p 2222
# Password comuni tipo "123456" vengono accettate dal finto SSH. Digita qualche comando, poi exit.

# 1) L'evento e' nel log di Cowrie?
docker exec cowrie tail -3 /home/cowrie/cowrie-git/var/log/cowrie/cowrie.json
# 2) L'alert e' arrivato a Wazuh? (le regole custom 100010-100013 del progetto)
sudo tail -n 100 /var/ossec/logs/alerts/alerts.json | grep -i cowrie
# Atteso: la catena honeypot -> Wazuh e' intatta
```

Se l'evento e' in Cowrie ma non in Wazuh: la pipeline log e' rotta -> [Honeypot / log-pipeline](../../Honeypot/docs/log-pipeline.md).

## 8. Segmentazione (VLAN): l'isolamento tiene?

La segmentazione serve a poco se un host su una VLAN puo' comunque raggiungere l'altra. Va provato l'isolamento.

```bash
# Da un host nella VLAN 150 (192.168.150.0/24), prova a raggiungere la LAN principale
ping -c2 192.168.0.102
# Atteso (se la segmentazione e' voluta stagna): NESSUNA risposta / bloccato
# Risposta -> la VLAN non e' isolata come credi (regole inter-VLAN troppo permissive)

# Sul Pi: l'interfaccia VLAN e la rete Docker sono quelle attese
ip -br link show end0.150
docker network inspect ipvlan_150 --format '{{.IPAM.Config}}'
```

## 9. Pi-hole: il sinkhole filtra?

```bash
# Da un client (non dall'host, per il MacVLAN)
dig @192.168.0.250 ads.doubleclick.net +short   # atteso 0.0.0.0 (bloccato)
dig @192.168.0.250 github.com +short             # atteso IP reale (non bloccato)
```

---

## Scorecard: registra il risultato

Trasforma il drill in un artefatto ripetibile. Dopo ogni esecuzione, compila:

```
DATA: __________
[ ] 1. Firewall: solo porte previste aperte, default-deny confermato
[ ] 2. Fail2ban: ban scattato su login falliti
[ ] 3. SSH: password/root rifiutati, config effettiva corretta
[ ] 4. Kernel: sysctl hardening applicati
[ ] 5. FIM: alert su modifica file in /etc
[ ] 6. Detection: alert su evento auth
[ ] 7. Honeypot: evento propagato Cowrie -> Wazuh
[ ] 8. VLAN: isolamento inter-VLAN confermato
[ ] 9. Pi-hole: sinkhole attivo
```

Un check che fallisce non e' un fallimento del drill: e' esattamente il motivo per cui il drill esiste. Documenta la causa e correggila.

---

## Prevenzione / cadenza

- Esegui questo runbook **dopo ogni** aggiornamento OS, cambio regole, o ripristino da backup.
- Automatizza i check non distruttivi (1, 3, 4, 9) con `scripts/setup.sh verify`; i test attivi (2, 5, 6, 7) restano manuali e periodici.
- Tieni la scorecard sotto versione: una regressione tra due drill e' un segnale prezioso.

---

## Collegamenti

- Red teaming completo del proprio lab -> [Security Assessment & Hardening](../../Security%20Assessment%20%26%20Hardening/)
- Rilevare una compromissione gia' avvenuta -> [Runbook 06: integrita' post-downtime](integrita-post-downtime.md)
- Baseline e checklist di stato -> [checklist post-installazione](../../docs/checklist-post-installazione.md)
