# SOC Analyst — Security Operations Center

Questa sezione raccoglie gli strumenti e le configurazioni relativi al monitoraggio centralizzato della sicurezza — il cuore di un SOC (Security Operations Center), anche se in scala "home lab".

---

## Cos'e' un SOC

Un SOC e' il centro nevralgico delle operazioni di sicurezza di un'organizzazione. Il suo compito e' **rilevare, analizzare e rispondere** agli incidenti di sicurezza in tempo reale.

In un'azienda, un SOC e' composto da:

- **Persone**: analisti di livello 1 (triage), livello 2 (investigazione), livello 3 (threat hunting)
- **Processi**: playbook di risposta agli incidenti, escalation, comunicazione
- **Tecnologia**: SIEM (raccolta e correlazione log), SOAR (automazione risposte), EDR (protezione endpoint)

Nel nostro home lab, ricreiamo la componente tecnologica usando **Wazuh** come SIEM/XDR open-source, integrato con tutti i servizi del Raspberry Pi.

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

**[Wazuh — Installazione e Configurazione](./Wazuh/)**

---

## Workflow tipico di analisi (per il nostro lab)

1. **Alert** appare sulla dashboard Wazuh (es. "Cowrie: INTRUSIONE RIUSCITA")
2. **Triage**: controllare l'IP sorgente — e' un bot noto? E' dalla rete locale o da Internet?
3. **Investigazione**: nella sezione Threat Hunting, filtrare per quell'IP e vedere tutti gli eventi correlati
4. **Correlazione**: l'IP ha anche tentato di accedere a SSH reale (porta 22)? Ha triggerato regole firewall?
5. **Risposta**: se l'IP e' sospetto, bloccare manualmente su UFW (`sudo ufw deny from <IP>`) o verificare che Fail2ban l'abbia gia' bannato
6. **Documentazione**: annotare l'incidente per future reference

Questo e' il ciclo di lavoro di un analista SOC, scalato per un home lab ma concettualmente identico a quello enterprise.
