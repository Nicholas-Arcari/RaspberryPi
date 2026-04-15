>  [English](README.en.md) |  **Italiano**

# SOC Analyst - Security Operations Center

Questa sezione raccoglie gli strumenti e le configurazioni relativi al monitoraggio centralizzato della sicurezza - il cuore di un SOC (Security Operations Center), anche se in scala "home lab".

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

## Indice della documentazione

| Documento | Contenuto |
|---|---|
| [Cos'è un SOC e i Tier](docs/tier-soc.md) | Definizione di SOC, ruoli L1/L2/L3 con responsabilità, skill richieste e applicazione nel nostro lab |
| [Log Pipeline](docs/log-pipeline.md) | Le 6 fasi del flusso dati (raccolta, decodifica, regole, arricchimento, indicizzazione, visualizzazione) e tabella diagnostica |
| [Alert Fatigue e Tuning](docs/alert-fatigue.md) | Strategie di tuning: livelli di severità, esclusioni syscheck, aggregazione con regole composite, esempi XML |
| [Confronto SIEM: Wazuh vs Splunk](docs/confronto-siem.md) | Confronto architetturale, motivazioni della scelta, percorso di migrazione a Splunk, configurazioni equivalenti |
| [Incident Response Playbook](docs/incident-response.md) | Framework NIST SP 800-61, 3 playbook operativi (honeypot, SSH brute force, FIM), matrice di escalation |

---

## Strumenti

### Wazuh SIEM/XDR

La piattaforma principale. Installazione e configurazione dettagliata nella sotto-sezione dedicata:

**[Wazuh - Installazione e Configurazione](./Wazuh/)**

---

## Workflow tipico di analisi (per il nostro lab)

1. **Alert** appare sulla dashboard Wazuh (es. "Cowrie: INTRUSIONE RIUSCITA")
2. **Triage**: controllare l'IP sorgente - è un bot noto? è dalla rete locale o da Internet?
3. **Investigazione**: nella sezione Threat Hunting, filtrare per quell'IP e vedere tutti gli eventi correlati
4. **Correlazione**: l'IP ha anche tentato di accedere a SSH reale (porta 22)? Ha triggerato regole firewall?
5. **Risposta**: se l'IP è sospetto, bloccare manualmente su UFW (`sudo ufw deny from <IP>`) o verificare che Fail2ban l'abbia già bannato
6. **Documentazione**: annotare l'incidente per future reference

Questo è il ciclo di lavoro di un analista SOC, scalato per un home lab ma concettualmente identico a quello enterprise.
