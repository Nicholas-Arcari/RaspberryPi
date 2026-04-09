# SOC Analyst - Security Operations Center

Questa sezione raccoglie gli strumenti e le configurazioni relativi al monitoraggio centralizzato della sicurezza - il cuore di un SOC (Security Operations Center), anche se in scala "home lab".

---

## Cos'e' un SOC

Un SOC e' il centro nevralgico delle operazioni di sicurezza di un'organizzazione. Il suo compito e' **rilevare, analizzare e rispondere** agli incidenti di sicurezza in tempo reale.

In un'azienda, un SOC e' composto da:

- **Persone**: analisti di livello 1 (triage), livello 2 (investigazione), livello 3 (threat hunting)
- **Processi**: playbook di risposta agli incidenti, escalation, comunicazione
- **Tecnologia**: SIEM (raccolta e correlazione log), SOAR (automazione risposte), EDR (protezione endpoint)

Nel nostro home lab, ricreiamo la componente tecnologica usando **Wazuh** come SIEM/XDR open-source, integrato con tutti i servizi del Raspberry Pi.

---

## I Tier del SOC: ruoli e responsabilita'

In un SOC enterprise, gli analisti sono organizzati in livelli con responsabilita' crescenti. Nel nostro home lab ricopriamo tutti i ruoli, ma comprendere la distinzione e' fondamentale per chi vuole lavorare nel settore.

### L1 - Triage Analyst

| Aspetto | Dettaglio |
|---|---|
| **Responsabilita' principale** | Monitoraggio continuo degli alert e primo filtro |
| **Attivita' tipiche** | Classificare gli alert (true/false positive), aprire i ticket, applicare playbook predefiniti |
| **Decisione chiave** | "Questo alert e' un vero incidente o rumore di fondo?" |
| **Skill richieste** | Lettura di log, conoscenza delle regole SIEM, familiarita' con MITRE ATT&CK |
| **Tempo medio per alert** | 5-15 minuti |
| **Escalation** | Se l'alert richiede investigazione approfondita → passa a L2 |

**Nel nostro lab**: quando appare un alert sulla dashboard Wazuh (es. "Cowrie: Login success"), il lavoro L1 consiste nel controllare l'IP sorgente, verificare se e' un bot noto (consultando threat intelligence come AbuseIPDB), e decidere se richiede azione.

### L2 - Incident Responder

| Aspetto | Dettaglio |
|---|---|
| **Responsabilita' principale** | Investigazione approfondita degli incidenti escalati da L1 |
| **Attivita' tipiche** | Correlazione eventi da fonti multiple, analisi forense iniziale, contenimento dell'incidente |
| **Decisione chiave** | "Qual e' l'estensione della compromissione e come la conteniamo?" |
| **Skill richieste** | Threat hunting, analisi di rete (Wireshark/tcpdump), scripting (Python/Bash), forensics base |
| **Tempo medio per incidente** | 1-8 ore |
| **Escalation** | Se la minaccia e' avanzata (APT, zero-day) → passa a L3 |

**Nel nostro lab**: dopo che L1 identifica un IP sospetto, il lavoro L2 consiste nel cercare tutti gli eventi correlati (firewall, honeypot, SSH) per ricostruire la kill chain completa dell'attaccante, come documentato nella sezione [Security Assessment](../Security%20Assessment%20%26%20Hardening/).

### L3 - Threat Hunter / Senior Analyst

| Aspetto | Dettaglio |
|---|---|
| **Responsabilita' principale** | Ricerca proattiva di minacce non rilevate dagli alert automatici |
| **Attivita' tipiche** | Creazione di regole custom, tuning del SIEM, analisi malware, threat intelligence, risposta a incidenti complessi |
| **Decisione chiave** | "Ci sono minacce attive che il nostro sistema non sta rilevando?" |
| **Skill richieste** | Reverse engineering, analisi malware, sviluppo regole YARA/Sigma, architettura SIEM, leadership tecnica |
| **Approccio** | Hypothesis-driven: parte da un'ipotesi ("Un attaccante potrebbe usare DNS tunneling per esfiltrare dati") e cerca prove nei log |

**Nel nostro lab**: il lavoro L3 e' la creazione delle regole custom in `/var/ossec/etc/rules/local_rules.xml` (le regole 100011-100014 per Cowrie), il tuning dei livelli di severita', e l'analisi dei pattern di attacco nei log dell'honeypot per identificare campagne coordinate.

---

## Log Pipeline: il flusso dei dati dalla sorgente alla Dashboard

Capire come i log viaggiano dalla sorgente all'alert visualizzato sulla dashboard e' essenziale per diagnosticare problemi ("perche' non vedo questo evento?") e per progettare nuove integrazioni.

```
SORGENTI                    RACCOLTA              ELABORAZIONE           STORAGE            VISUALIZZAZIONE
─────────────────────────────────────────────────────────────────────────────────────────────────────────

/var/log/auth.log  ──┐
/var/log/ufw.log   ──┤
/var/log/syslog    ──┤      Wazuh Agent          Wazuh Manager          Wazuh Indexer      Wazuh Dashboard
/var/log/fail2ban  ──┼──►  (ossec-logcollector  ──► (ossec-analysisd    ──► (OpenSearch     ──► (OpenSearch
/var/log/cowrie/   ──┤      inotify/polling)       decoder + rules)      Filebeat)           Dashboards)
Docker logs        ──┤
FIM (syscheck)     ──┘      Porta 1514/TCP        local_rules.xml        Indici             Query, filtri,
                             ▲                     local_decoder.xml      wazuh-alerts-*     grafici, report
                             │                          │                      │
                             │                          ▼                      ▼
                        Registrazione            Alert JSON              Retention policy
                        agenti: 1515/TCP         (livello ≥ 3)          (90 giorni default)
```

### Le 6 fasi del pipeline in dettaglio

**Fase 1 - Raccolta (Agent)**: Il demone `ossec-logcollector` sull'agente monitora i file di log configurati in `ossec.conf` (sezione `<localfile>`). Usa `inotify` per rilevare nuove righe in tempo reale (non polling periodico, quindi latenza quasi zero). I log vengono compressi con zlib e cifrati con AES-256-CBC prima dell'invio al Manager.

**Fase 2 - Decodifica (Manager)**: Il demone `ossec-analysisd` riceve gli eventi e li passa attraverso i **decoder** - regex che estraggono campi strutturati dal testo grezzo. Esempio: dal testo `Failed password for root from 192.168.0.50 port 54321 ssh2`, il decoder SSH estrae `user=root`, `srcip=192.168.0.50`, `srcport=54321`.

**Fase 3 - Regole (Manager)**: I campi decodificati vengono confrontati con la **rule chain** - migliaia di regole ordinate per ID. Le regole possono essere atomiche ("se vedi X, alerta") o composite ("se vedi X piu' di 5 volte in 60 secondi, alerta"). Solo gli eventi che matchano una regola con livello >= 3 generano un alert.

**Fase 4 - Arricchimento (Manager)**: L'alert JSON viene arricchito con metadati: mapping MITRE ATT&CK, informazioni sull'agente, GeoIP dell'IP sorgente (se configurato), punteggio CVSS per vulnerabilita'.

**Fase 5 - Indicizzazione (Filebeat → Indexer)**: Filebeat legge gli alert JSON da `/var/ossec/logs/alerts/alerts.json` e li invia all'Indexer (OpenSearch) via HTTPS con autenticazione TLS mutua. L'Indexer indicizza i campi per ricerche rapide e li archivia in indici giornalieri (`wazuh-alerts-4.x-2025.04.08`).

**Fase 6 - Visualizzazione (Dashboard)**: La Dashboard legge gli indici dall'Indexer e presenta gli alert in tempo reale con filtri, grafici temporali, e drill-down per campo.

### Dove si rompe (diagnostica)

| Sintomo | Fase rotta | Come verificare |
|---|---|---|
| Nessun alert sulla Dashboard | Qualsiasi | Partire dal fondo: l'indice esiste? Filebeat gira? Il Manager riceve eventi? |
| L'agente risulta "Disconnected" | Fase 1 | `sudo systemctl status wazuh-agent`, verificare porte 1514/1515 su UFW |
| L'evento arriva ma non genera alert | Fase 3 | Testare con `wazuh-logtest` - il log matcha una regola? Il livello e' >= 3? |
| L'alert appare nei log ma non sulla Dashboard | Fase 5 | `sudo systemctl status filebeat`, controllare la connessione Filebeat → Indexer |
| Query sulla Dashboard non trova risultati | Fase 6 | Verificare il range temporale selezionato, controllare il nome dell'indice |

---

## Alert Fatigue e Tuning: il problema piu' sottovalutato

### Cos'e' l'alert fatigue

L'alert fatigue si verifica quando un analista riceve **troppi alert** (la maggior parte dei quali sono falsi positivi o eventi a bassa priorita'), al punto da iniziare a ignorarli sistematicamente. In un SOC enterprise, un analista L1 puo' ricevere 500-1000+ alert al giorno. Se il 95% sono falsi positivi, la probabilita' che ignori il 5% di veri incidenti e' alta.

**Nel nostro lab** il problema si manifesta in scala ridotta ma reale: Cowrie genera decine di alert per ogni bot che scansiona la porta 2222. Se ogni singolo tentativo di login fallito genera un alert livello 5, la dashboard diventa inutilizzabile in poche ore.

### Strategie di tuning

**1. Regolare i livelli di severita':**

Le regole Wazuh hanno livelli da 0 (nessun alert) a 15 (emergenza). Il tuning consiste nell'alzare la soglia di notifica e regolare i livelli in base al contesto:

```xml
<!-- Esempio: ridurre il rumore dei login falliti sull'honeypot -->
<!-- Prima (troppo rumoroso): ogni singolo fallimento genera alert livello 5 -->
<rule id="100011" level="5">
  <decoded_as>cowrie</decoded_as>
  <field name="eventid">cowrie.login.failed</field>
  <description>Cowrie: Failed login attempt</description>
</rule>

<!-- Dopo (tuned): alert solo dopo 10 fallimenti in 120 secondi dallo stesso IP -->
<rule id="100011" level="5" frequency="10" timeframe="120">
  <decoded_as>cowrie</decoded_as>
  <field name="eventid">cowrie.login.failed</field>
  <same_source_ip />
  <description>Cowrie: Brute force detected (10+ failures in 2 min)</description>
</rule>
```

**2. Esclusioni mirate (regole syscheck):**

Il File Integrity Monitoring (syscheck) genera alert ogni volta che un file monitorato cambia. File che cambiano legittimamente (log che ruotano, file temporanei, cache) producono falsi positivi continui:

```xml
<!-- Escludere directory con cambiamenti legittimi e frequenti -->
<syscheck>
  <ignore>/var/log</ignore>
  <ignore>/tmp</ignore>
  <ignore>/var/cache</ignore>
  <ignore type="sregex">.swp$</ignore>  <!-- File temporanei di vim -->
</syscheck>
```

**3. Aggregazione e correlazione:**

Invece di generare un alert per ogni singolo evento, raggruppare eventi correlati. Wazuh supporta regole composite con `<if_matched_sid>`:

```xml
<!-- Regola figlio: si attiva solo se la regola 100012 (login success)
     e' stata triggerata dallo stesso IP che ha anche triggerato
     la regola 100013 (command executed) entro 300 secondi -->
<rule id="100015" level="12">
  <if_matched_sid>100012</if_matched_sid>
  <same_source_ip />
  <description>Cowrie: Attaccante ha eseguito comandi dopo login - possibile sessione interattiva</description>
  <mitre>
    <id>T1059</id>  <!-- Command and Scripting Interpreter -->
  </mitre>
</rule>
```

> **Regola d'oro del tuning**: un alert deve richiedere un'azione. Se un analista guarda un alert e la risposta e' sistematicamente "ignora", quella regola va tuned (livello abbassato, soglia alzata, o esclusa). Il tuning non e' un'attivita' una tantum - e' un processo continuo che migliora nel tempo man mano che si capiscono i pattern del proprio ambiente

---

## Cosa monitoriamo

| Sorgente | Cosa genera | Tipo di alert |
|---|---|---|
| SSH (auth.log) | Tentativi di login falliti/riusciti | Brute force, accesso non autorizzato |
| Fail2ban | Ban automatici di IP | Attacchi automatizzati in corso |
| UFW (firewall) | Connessioni bloccate/permesse | Scansioni di porta, traffico anomalo |
| Cowrie (Honeypot) | Intrusioni, comandi eseguiti, credenziali | Attaccanti attivi sulla rete |
| Syscheck (FIM) | Modifiche a file di sistema | Compromissione post-exploitation |
| Docker | Log dei container, errori | Malfunzionamenti, tentativi di escape |

---

## Perche' Wazuh e non Splunk (o altri SIEM)

La scelta del SIEM e' una decisione architetturale critica. Wazuh non e' stato scelto "perche' e' gratis" — e' stato scelto per ragioni tecniche specifiche al nostro caso d'uso.

### Confronto architetturale

| Aspetto | Wazuh | Splunk Enterprise | Splunk Free | Elastic SIEM |
|---|---|---|---|---|
| **Licenza** | Open source (GPLv2) | Commerciale (~$2000/GB/anno) | Gratuito, 500MB/giorno | Open source (SSPL) |
| **Costo per il nostro lab** | $0 | ~$15.000+/anno (impensabile) | $0 ma molto limitato | $0 |
| **ARM64 (Raspberry Pi)** | Pacchetti .deb ARM64 disponibili | **NON disponibile** su ARM | **NON disponibile** su ARM | Pacchetti ARM64 disponibili |
| **Agent integrato** | Si (FIM, rootcheck, vulnerability detection) | Universal Forwarder (solo log shipping) | Universal Forwarder | Elastic Agent |
| **IDS/IPS integrato** | Parziale (log analysis rules) | No (richiede add-on) | No | No |
| **Active Response** | Si (blocco IP automatico) | No nativo (richiede SOAR) | No | No nativo |
| **Compliance** | PCI DSS, GDPR, HIPAA, CIS | Si (con add-on a pagamento) | No | Parziale |
| **Storage backend** | OpenSearch (fork Elasticsearch) | Proprietario (Splunk indexes) | Proprietario | Elasticsearch |
| **Query language** | OpenSearch DSL (JSON) | SPL (Splunk Processing Language) | SPL | KQL / EQL |
| **Risorse su RPi 5 (8GB)** | ~4-5GB RAM totali | N/A (non gira su ARM) | N/A | ~3-4GB RAM |

### La motivazione reale

1. **ARM64**: Splunk semplicemente non gira su Raspberry Pi. Fine della discussione per il nostro hardware. Se avessimo un server x86_64 con 32GB di RAM, Splunk Enterprise sarebbe una scelta valida

2. **All-in-one**: Wazuh non e' solo un SIEM — e' anche un XDR. L'agent fa FIM, vulnerability detection, rootcheck, log collection e compliance in un unico pacchetto. Con Splunk, dovresti installare separatamente: Universal Forwarder + OSSEC/Tripwire (FIM) + Nessus/OpenVAS (vulnerability) + tool di compliance

3. **Active Response**: Wazuh puo' bloccare un IP automaticamente quando un alert raggiunge una certa soglia. Splunk richiede un SOAR separato (Splunk SOAR, ex Phantom) — un altro prodotto a pagamento

4. **Costo**: Per un home lab educativo, il costo di Splunk e' proibitivo. Wazuh offre il 90% delle funzionalita' a costo zero

### Se volessi migrare a Splunk (su hardware x86_64)

Le modifiche architetturali necessarie:

```
ATTUALE (Wazuh):
Agent → Manager :1514 → Filebeat → OpenSearch :9200 → Dashboard :443

SPLUNK:
Universal Forwarder → Splunk Indexer :9997 → Splunk Search Head :8000
                                       ↑
                              Splunk Heavy Forwarder
                              (parsing e filtering)
```

| Componente Wazuh | Sostituito da | Configurazione |
|---|---|---|
| Wazuh Agent | Splunk Universal Forwarder | `inputs.conf`: monitor dei log, `outputs.conf`: puntamento all'Indexer |
| Wazuh Manager (decoder + rules) | Splunk Heavy Forwarder + `props.conf`/`transforms.conf` | Regole di parsing (regex per estrarre campi), lookup tables per enrichment |
| OpenSearch (Indexer) | Splunk Indexer | `indexes.conf`: definizione indici, retention policy, volume di storage |
| Wazuh Dashboard | Splunk Search Head | Dashboard custom in Simple XML o Dashboard Studio |
| Filebeat | Non necessario | Il Forwarder invia direttamente all'Indexer |
| Regole custom (local_rules.xml) | Correlation searches + Notable events | SPL queries schedulati in Enterprise Security |
| Active Response | Splunk SOAR (Phantom) | Playbook automatici (prodotto separato, a pagamento) |

**File chiave da creare/modificare per Splunk:**

```ini
# inputs.conf (sul Forwarder - equivale a <localfile> in ossec.conf)
[monitor:///var/log/auth.log]
sourcetype = linux_secure
index = security

[monitor:///var/log/cowrie/cowrie.json]
sourcetype = cowrie:json
index = honeypot

# props.conf (parsing - equivale ai decoder Wazuh)
[cowrie:json]
KV_MODE = json
TIME_FORMAT = %Y-%m-%dT%H:%M:%S.%6N%Z
TIME_PREFIX = "timestamp":"

# savedsearches.conf (correlation - equivale alle regole Wazuh)
[Honeypot Login Success]
search = index=honeypot sourcetype=cowrie:json eventid=cowrie.login.success
alert_threshold = 1
action.email = 1
cron_schedule = */5 * * * *
```

> **Nota per chi studia:** In un colloquio per SOC analyst, saper spiegare le differenze architetturali tra Wazuh e Splunk (e quando usare l'uno o l'altro) e' un punto a favore. Wazuh per lab/PMI con budget limitato e bisogno di agent integrati. Splunk per enterprise con budget, volumi di dati elevati e necessita' di SPL per query complesse.

## Strumenti

### Wazuh SIEM/XDR

La piattaforma principale. Installazione e configurazione dettagliata nella sotto-sezione dedicata:

**[Wazuh - Installazione e Configurazione](./Wazuh/)**

---

## Workflow tipico di analisi (per il nostro lab)

1. **Alert** appare sulla dashboard Wazuh (es. "Cowrie: INTRUSIONE RIUSCITA")
2. **Triage**: controllare l'IP sorgente - e' un bot noto? E' dalla rete locale o da Internet?
3. **Investigazione**: nella sezione Threat Hunting, filtrare per quell'IP e vedere tutti gli eventi correlati
4. **Correlazione**: l'IP ha anche tentato di accedere a SSH reale (porta 22)? Ha triggerato regole firewall?
5. **Risposta**: se l'IP e' sospetto, bloccare manualmente su UFW (`sudo ufw deny from <IP>`) o verificare che Fail2ban l'abbia gia' bannato
6. **Documentazione**: annotare l'incidente per future reference

Questo e' il ciclo di lavoro di un analista SOC, scalato per un home lab ma concettualmente identico a quello enterprise.

---

## Incident Response Playbook

Questo playbook definisce **cosa fare concretamente** quando Wazuh genera un alert critico. Segue il framework NIST SP 800-61 (Computer Security Incident Handling Guide), adattato al nostro home lab.

### Le 6 fasi dell'Incident Response

```
[1] Preparazione → [2] Identificazione → [3] Contenimento → [4] Eradicazione → [5] Recovery → [6] Lessons Learned
        │                   │                    │                   │                │                │
   Strumenti pronti    "E' un vero          Limitare il        Rimuovere la      Ripristinare      Cosa migliorare
   Contatti definiti    incidente?"         danno ORA          causa root        il servizio       per la prossima
   Playbook scritto                                                                                volta
```

### Playbook 1: Intrusione Honeypot (alert rule 100012, livello 10)

**Trigger:** Alert Wazuh "Cowrie: Login success detected on honeypot"

**Fase 1 — Identificazione (5 minuti)**

```bash
# 1. Leggi l'alert sulla Dashboard o dai log
sudo tail -20 /var/ossec/logs/alerts/alerts.json | python3 -m json.tool | grep -A5 "cowrie"

# 2. Estrai l'IP sorgente dell'attaccante
# Dalla Dashboard: Threat Hunting → filtro "rule.id: 100012" → campo data.cowrie.src_ip

# 3. Verifica se l'IP e' un bot noto
# Cerca su https://www.abuseipdb.com/check/<IP>
# Oppure da terminale:
curl -s "https://api.abuseipdb.com/api/v2/check?ipAddress=<IP>" \
  -H "Key: <TUA_API_KEY>" -H "Accept: application/json" | python3 -m json.tool
```

**Decisione:** L'IP e' un bot automatico (confidence score > 80% su AbuseIPDB) o un attacco mirato (IP mai visto, comandi sofisticati)?

**Fase 2 — Contenimento (10 minuti)**

```bash
# 4. IMMEDIATO: blocca l'IP sul firewall
sudo ufw deny from <IP_ATTACCANTE> comment "Honeypot intrusion - $(date +%Y-%m-%d)"

# 5. Verifica che l'attaccante NON abbia raggiunto l'host reale
# Controlla i log SSH del sistema (porta 22, non 2222)
grep "<IP_ATTACCANTE>" /var/log/auth.log

# 6. Verifica che non ci siano connessioni attive dall'IP
ss -tn | grep "<IP_ATTACCANTE>"

# 7. Controlla se il container Cowrie e' ancora integro
docker inspect cowrie --format '{{.State.Status}}'  # Deve essere "running"
docker logs cowrie --tail 20                         # Cercare errori anomali
```

**Fase 3 — Eradicazione (15 minuti)**

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

**Fase 4 — Recovery**

```bash
# 11. Se il container e' compromesso, ricrealo da zero (i dati sono nel volume)
docker stop cowrie && docker rm cowrie
docker pull cowrie/cowrie:latest
# Ricrea con lo stesso docker-compose

# 12. Verifica che Wazuh stia ancora ingestendo i log
sudo /var/ossec/bin/wazuh-logtest
# Incolla una riga di log Cowrie e verifica che la regola matchi
```

**Fase 5 — Lessons Learned**

Dopo l'incidente, rispondi a queste domande:
- L'alert e' arrivato in tempo? Se no, serve una regola con frequenza piu' alta?
- Il firewall ha bloccato l'IP abbastanza velocemente? Serve una regola automatica?
- L'attaccante ha usato tecniche non coperte dalle regole Wazuh? Serve una nuova regola custom?

### Playbook 2: Brute force su SSH reale (alert rule 5712, livello 10)

**Trigger:** Alert Wazuh "sshd: Multiple authentication failures"

**Questo e' piu' grave dell'honeypot** — l'attaccante sta colpendo il servizio SSH reale (porta 22), non la trappola.

```bash
# 1. IMMEDIATO: verifica che Fail2ban abbia gia' bannato l'IP
sudo fail2ban-client status sshd | grep "<IP>"

# 2. Se non bannato, blocca manualmente
sudo ufw deny from <IP_ATTACCANTE> comment "SSH brute force - $(date +%Y-%m-%d)"

# 3. Verifica che NESSUN login sia riuscito
grep "Accepted" /var/log/auth.log | grep "<IP_ATTACCANTE>"
# Se trovi risultati: ESCALATION IMMEDIATA — l'attaccante e' dentro

# 4. Se il login e' riuscito (worst case):
#    a. Identifica l'utente compromesso
#    b. Blocca l'utente: sudo passwd -l <utente>
#    c. Termina le sessioni attive: sudo pkill -u <utente>
#    d. Cambia TUTTE le password e rigenera le chiavi SSH
#    e. Controlla crontab e authorized_keys dell'utente per persistence
sudo crontab -l -u <utente>
cat /home/<utente>/.ssh/authorized_keys   # Cercare chiavi sconosciute
#    f. Avvia scan FIM immediato: sudo /var/ossec/bin/wazuh-control restart
```

### Playbook 3: Modifica file di sistema (alert rule 550-554, FIM)

**Trigger:** Alert Wazuh "File modified" su `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config` o binari in `/usr/bin`

```bash
# 1. Identifica COSA e' cambiato
# Dalla Dashboard: campo syscheck.path, syscheck.diff (se abilitato)

# 2. Identifica CHI ha cambiato il file
# Campo syscheck.audit.user.name (richiede auditd)
# Oppure: controlla auth.log per comandi sudo recenti
grep "sudo" /var/log/auth.log | tail -20

# 3. Il cambiamento e' legittimo?
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

### Matrice di escalation

| Livello alert | Tipo | Azione | Tempo risposta |
|---|---|---|---|
| 3-5 | Info/Low | Registrare, controllare a fine giornata | 24 ore |
| 6-9 | Medium | Investigare entro 1 ora, correlare con altri eventi | 1 ora |
| 10-12 | High | Contenimento immediato (blocco IP/utente), investigazione completa | 15 minuti |
| 13-15 | Critical | Tutto il traffico in ingresso bloccato, analisi forense, considera di staccare il Pi dalla rete | Immediato |

> **Regola operativa:** Un playbook che non e' stato testato non funziona. Almeno una volta al mese, simula un incidente (connettiti all'honeypot da una rete esterna, modifica un file monitorato) e segui il playbook dall'inizio alla fine. Ogni volta troverai passaggi che mancano o che non funzionano come previsto
