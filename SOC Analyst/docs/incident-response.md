>  [English](incident-response.en.md) |  **Italiano**

# Incident Response Playbook

Questo playbook definisce **cosa fare concretamente** quando Wazuh genera un alert critico. Segue il framework NIST SP 800-61 (Computer Security Incident Handling Guide), adattato al nostro home lab.

## Le 6 fasi dell'Incident Response

```
[1] Preparazione → [2] Identificazione → [3] Contenimento → [4] Eradicazione → [5] Recovery → [6] Lessons Learned
        │                   │                    │                   │                │                │
   Strumenti pronti    "è un vero          Limitare il        Rimuovere la      Ripristinare      Cosa migliorare
   Contatti definiti    incidente?"         danno ORA          causa root        il servizio       per la prossima
   Playbook scritto                                                                                volta
```

## Playbook 1: Intrusione Honeypot (alert rule 100012, livello 10)

**Trigger:** Alert Wazuh "Cowrie: Login success detected on honeypot"

**Fase 1 - Identificazione (5 minuti)**

```bash
# 1. Leggi l'alert sulla Dashboard o dai log
sudo tail -20 /var/ossec/logs/alerts/alerts.json | python3 -m json.tool | grep -A5 "cowrie"

# 2. Estrai l'IP sorgente dell'attaccante
# Dalla Dashboard: Threat Hunting → filtro "rule.id: 100012" → campo data.cowrie.src_ip

# 3. Verifica se l'IP è un bot noto
# Cerca su https://www.abuseipdb.com/check/<IP>
# Oppure da terminale:
curl -s "https://api.abuseipdb.com/api/v2/check?ipAddress=<IP>" \
  -H "Key: <TUA_API_KEY>" -H "Accept: application/json" | python3 -m json.tool
```

**Decisione:** L'IP è un bot automatico (confidence score > 80% su AbuseIPDB) o un attacco mirato (IP mai visto, comandi sofisticati)?

**Fase 2 - Contenimento (10 minuti)**

```bash
# 4. IMMEDIATO: blocca l'IP sul firewall
sudo ufw deny from <IP_ATTACCANTE> comment "Honeypot intrusion - $(date +%Y-%m-%d)"

# 5. Verifica che l'attaccante NON abbia raggiunto l'host reale
# Controlla i log SSH del sistema (porta 22, non 2222)
grep "<IP_ATTACCANTE>" /var/log/auth.log

# 6. Verifica che non ci siano connessioni attive dall'IP
ss -tn | grep "<IP_ATTACCANTE>"

# 7. Controlla se il container Cowrie è ancora integro
docker inspect cowrie --format '{{.State.Status}}'  # Deve essere "running"
docker logs cowrie --tail 20                         # Cercare errori anomali
```

**Fase 3 - Eradicazione (15 minuti)**

```bash
# 8. Analizza la sessione completa sulla Dashboard
#    Filtro: data.cowrie.src_ip: "<IP_ATTACCANTE>"
#    Ordina per timestamp crescente
#    Cerca: comandi eseguiti, file scaricati, tentativi di escape

# 9. Se l'attaccante ha scaricato file nel honeypot, catturali per analisi
docker exec cowrie ls -la /home/cowrie/cowrie-git/var/lib/cowrie/downloads/
# I file scaricati dall'attaccante sono salvati qui con hash SHA-256 come nome

# 10. Se sospetti container escape (eventi anomali nei log dell'host):
# Controlla processi sospetti
ps auxf | grep -v grep | grep -E "(nc|ncat|bash -i|python.*socket)"
# Controlla connessioni di rete anomale
ss -tlnp | grep -v -E "(sshd|docker|wazuh|filebeat)"
# Controlla file modificati di recente in directory critiche
find /etc /usr/bin /usr/sbin -mmin -30 -ls 2>/dev/null
```

**Fase 4 - Recovery**

```bash
# 11. Se il container è compromesso, ricrealo da zero (i dati sono nel volume)
docker stop cowrie && docker rm cowrie
docker pull cowrie/cowrie:latest
# Ricrea con lo stesso docker-compose

# 12. Verifica che Wazuh stia ancora ingestendo i log
sudo /var/ossec/bin/wazuh-logtest
# Incolla una riga di log Cowrie e verifica che la regola matchi
```

**Fase 5 - Lessons Learned**

Dopo l'incidente, rispondi a queste domande:
- L'alert è arrivato in tempo? Se no, serve una regola con frequenza più alta?
- Il firewall ha bloccato l'IP abbastanza velocemente? Serve una regola automatica?
- L'attaccante ha usato tecniche non coperte dalle regole Wazuh? Serve una nuova regola custom?

## Playbook 2: Brute force su SSH reale (alert rule 5712, livello 10)

**Trigger:** Alert Wazuh "sshd: Multiple authentication failures"

**Questo è più grave dell'honeypot** - l'attaccante sta colpendo il servizio SSH reale (porta 22), non la trappola.

```bash
# 1. IMMEDIATO: verifica che Fail2ban abbia già bannato l'IP
sudo fail2ban-client status sshd | grep "<IP>"

# 2. Se non bannato, blocca manualmente
sudo ufw deny from <IP_ATTACCANTE> comment "SSH brute force - $(date +%Y-%m-%d)"

# 3. Verifica che NESSUN login sia riuscito
grep "Accepted" /var/log/auth.log | grep "<IP_ATTACCANTE>"
# Se trovi risultati: ESCALATION IMMEDIATA - l'attaccante è dentro

# 4. Se il login è riuscito (worst case):
#    a. Identifica l'utente compromesso
#    b. Blocca l'utente: sudo passwd -l <utente>
#    c. Termina le sessioni attive: sudo pkill -u <utente>
#    d. Cambia TUTTE le password e rigenera le chiavi SSH
#    e. Controlla crontab e authorized_keys dell'utente per persistence
sudo crontab -l -u <utente>
cat /home/<utente>/.ssh/authorized_keys   # Cercare chiavi sconosciute
#    f. Avvia scan FIM immediato: sudo /var/ossec/bin/wazuh-control restart
```

## Playbook 3: Modifica file di sistema (alert rule 550-554, FIM)

**Trigger:** Alert Wazuh "File modified" su `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config` o binari in `/usr/bin`

```bash
# 1. Identifica COSA è cambiato
# Dalla Dashboard: campo syscheck.path, syscheck.diff (se abilitato)

# 2. Identifica CHI ha cambiato il file
# Campo syscheck.audit.user.name (richiede auditd)
# Oppure: controlla auth.log per comandi sudo recenti
grep "sudo" /var/log/auth.log | tail -20

# 3. Il cambiamento è legittimo?
#    - Hai appena fatto apt upgrade? → normale
#    - Hai modificato sshd_config via OMV? → normale
#    - Nessuno ha toccato il sistema? → INVESTIGARE

# 4. Se illegittimo:
#    a. Salva il file modificato per analisi forense
sudo cp /etc/<file_modificato> /tmp/evidence_$(date +%Y%m%d)
#    b. Ripristina dal backup o dal pacchetto
sudo apt install --reinstall <pacchetto_che_contiene_il_file>
#    c. Controlla se l'attaccante ha creato backdoor
sudo grep -r "0:0" /etc/passwd    # Cercare utenti con UID 0 (root) non legittimi
sudo find / -perm -4000 -ls 2>/dev/null   # Cercare binari SUID nuovi
```

## Matrice di escalation

| Livello alert | Tipo | Azione | Tempo risposta |
|---|---|---|---|
| 3-5 | Info/Low | Registrare, controllare a fine giornata | 24 ore |
| 6-9 | Medium | Investigare entro 1 ora, correlare con altri eventi | 1 ora |
| 10-12 | High | Contenimento immediato (blocco IP/utente), investigazione completa | 15 minuti |
| 13-15 | Critical | Tutto il traffico in ingresso bloccato, analisi forense, considera di staccare il Pi dalla rete | Immediato |

> **Regola operativa:** Un playbook che non è stato testato non funziona. Almeno una volta al mese, simula un incidente (connettiti all'honeypot da una rete esterna, modifica un file monitorato) e segui il playbook dall'inizio alla fine. Ogni volta troverai passaggi che mancano o che non funzionano come previsto
