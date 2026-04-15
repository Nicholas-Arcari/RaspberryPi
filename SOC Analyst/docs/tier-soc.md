>  [English](tier-soc.en.md) |  **Italiano**

# Cos'è un SOC

Un SOC è il centro nevralgico delle operazioni di sicurezza di un'organizzazione. Il suo compito è **rilevare, analizzare e rispondere** agli incidenti di sicurezza in tempo reale.

In un'azienda, un SOC è composto da:

- **Persone**: analisti di livello 1 (triage), livello 2 (investigazione), livello 3 (threat hunting)
- **Processi**: playbook di risposta agli incidenti, escalation, comunicazione
- **Tecnologia**: SIEM (raccolta e correlazione log), SOAR (automazione risposte), EDR (protezione endpoint)

Nel nostro home lab, ricreiamo la componente tecnologica usando **Wazuh** come SIEM/XDR open-source, integrato con tutti i servizi del Raspberry Pi.

---

## I Tier del SOC: ruoli e responsabilità

In un SOC enterprise, gli analisti sono organizzati in livelli con responsabilità crescenti. Nel nostro home lab ricopriamo tutti i ruoli, ma comprendere la distinzione è fondamentale per chi vuole lavorare nel settore.

### L1 - Triage Analyst

| Aspetto | Dettaglio |
|---|---|
| **Responsabilità principale** | Monitoraggio continuo degli alert e primo filtro |
| **Attività tipiche** | Classificare gli alert (true/false positive), aprire i ticket, applicare playbook predefiniti |
| **Decisione chiave** | "Questo alert è un vero incidente o rumore di fondo?" |
| **Skill richieste** | Lettura di log, conoscenza delle regole SIEM, familiarità con MITRE ATT&CK |
| **Tempo medio per alert** | 5-15 minuti |
| **Escalation** | Se l'alert richiede investigazione approfondita → passa a L2 |

**Nel nostro lab**: quando appare un alert sulla dashboard Wazuh (es. "Cowrie: Login success"), il lavoro L1 consiste nel controllare l'IP sorgente, verificare se è un bot noto (consultando threat intelligence come AbuseIPDB), e decidere se richiede azione.

### L2 - Incident Responder

| Aspetto | Dettaglio |
|---|---|
| **Responsabilità principale** | Investigazione approfondita degli incidenti escalati da L1 |
| **Attività tipiche** | Correlazione eventi da fonti multiple, analisi forense iniziale, contenimento dell'incidente |
| **Decisione chiave** | "Qual è l'estensione della compromissione e come la conteniamo?" |
| **Skill richieste** | Threat hunting, analisi di rete (Wireshark/tcpdump), scripting (Python/Bash), forensics base |
| **Tempo medio per incidente** | 1-8 ore |
| **Escalation** | Se la minaccia è avanzata (APT, zero-day) → passa a L3 |

**Nel nostro lab**: dopo che L1 identifica un IP sospetto, il lavoro L2 consiste nel cercare tutti gli eventi correlati (firewall, honeypot, SSH) per ricostruire la kill chain completa dell'attaccante, come documentato nella sezione [Security Assessment](../../Security%20Assessment%20%26%20Hardening/).

### L3 - Threat Hunter / Senior Analyst

| Aspetto | Dettaglio |
|---|---|
| **Responsabilità principale** | Ricerca proattiva di minacce non rilevate dagli alert automatici |
| **Attività tipiche** | Creazione di regole custom, tuning del SIEM, analisi malware, threat intelligence, risposta a incidenti complessi |
| **Decisione chiave** | "Ci sono minacce attive che il nostro sistema non sta rilevando?" |
| **Skill richieste** | Reverse engineering, analisi malware, sviluppo regole YARA/Sigma, architettura SIEM, leadership tecnica |
| **Approccio** | Hypothesis-driven: parte da un'ipotesi ("Un attaccante potrebbe usare DNS tunneling per esfiltrare dati") e cerca prove nei log |

**Nel nostro lab**: il lavoro L3 è la creazione delle regole custom in `/var/ossec/etc/rules/local_rules.xml` (le regole 100011-100014 per Cowrie), il tuning dei livelli di severità, e l'analisi dei pattern di attacco nei log dell'honeypot per identificare campagne coordinate.
