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
