>  [English](troubleshooting.en.md) |  **Italiano**

# Troubleshooting - SOC operations: problemi reali e soluzioni

> Problemi dal punto di vista dell'**analista**, non dell'amministratore: una sorgente log che smette di parlare, troppi falsi positivi, un attacco reale che non ha prodotto alert, eventi che non si correlano. E' il troubleshooting della *capacita' di rilevamento*, complementare al troubleshooting tecnico di installazione in [Wazuh / troubleshooting](../Wazuh/docs/troubleshooting.md).

Bussola: nel SOC, "nessun alert" ha due letture opposte e va sempre disambiguato. Puo' significare **tutto tranquillo** oppure **sono cieco**. Un analista non si fida del silenzio: lo verifica.

---

## Problema 1: Una sorgente ha smesso di generare eventi

**Sintomo:** non arrivano piu' alert da una sorgente che prima funzionava (es. nessun evento Cowrie, o nessun evento UFW da giorni).

**Causa:** rottura in un punto della pipeline a 6 fasi (raccolta -> decodifica -> regole -> arricchimento -> indicizzazione -> visualizzazione). Il guasto e' quasi sempre nella **raccolta**: il log non viene piu' scritto, o l'agent non lo legge piu'.

**Soluzione (segui la pipeline dalla sorgente in su):**

```bash
# 1. La sorgente scrive ancora il suo log?
tail -3 /var/log/auth.log                                   # SSH
docker exec cowrie tail -3 /home/cowrie/cowrie-git/var/log/cowrie/cowrie.json   # Cowrie
tail -3 /var/log/ufw.log                                    # UFW

# 2. L'agent Wazuh sta leggendo quel file? (deve esserci una <localfile> in ossec.conf)
sudo grep -A2 "<localfile>" /var/ossec/etc/ossec.conf | grep -i "auth.log\|cowrie\|ufw"

# 3. L'agent e' connesso e attivo?
sudo /var/ossec/bin/agent_control -l

# 4. Un evento di quella sorgente produce ancora un alert? (test decoder+regola)
echo '<riga di log di esempio>' | sudo /var/ossec/bin/wazuh-logtest
```

Se il log e' vuoto, il problema e' nel servizio sorgente (vedi il troubleshooting del modulo relativo). Se il log si popola ma l'alert non arriva, il problema e' decoder/regole (Problema 3).

---

## Problema 2: Troppi falsi positivi (alert fatigue)

**Sintomo:** la dashboard e' inondata di alert a bassa priorita' e gli eventi importanti si perdono nel rumore.

**Causa:** regole troppo rumorose o non tarate sul contesto del lab (es. il tuo stesso scan settimanale che triggera alert di rete).

**Soluzione:** applica il tuning invece di ignorare gli alert. Le leve principali:
- **Filtra per livello**: lavora sugli alert di livello >= 7-10 e relega i minori a report.
- **Esclusioni syscheck** mirate per i path che cambiano legittimamente e spesso.
- **Regole composite** per aggregare N eventi ripetuti in un solo alert.

Il metodo completo (livelli di severita', esclusioni, regole composite con esempi XML) e' in [alert-fatigue](alert-fatigue.md).

> Regola d'oro: **non silenziare un alert senza capirlo.** Ogni esclusione va motivata; una regola disabilitata "perche' rumorosa" e' un punto cieco creato apposta.

---

## Problema 3: Un attacco reale NON ha prodotto un alert (punto cieco)

**Sintomo:** hai eseguito un test (o subito un evento reale) che avrebbe dovuto generare un alert, ma nella dashboard non c'e' nulla.

**Causa:** il log arriva ma nessun **decoder** lo interpreta, o nessuna **regola** matcha, oppure la regola ha un livello sotto la soglia di alerting.

**Soluzione:**

```bash
# Riproduci l'evento contro il motore di regole e guarda cosa succede
sudo /var/ossec/bin/wazuh-logtest
# Incolla una riga di log reale dell'evento e osserva:
#   "Phase 2: decoder" -> quale decoder l'ha interpretata (se nessuno -> serve un decoder)
#   "Phase 3: rule"    -> quale regola ha matchato e a che livello (se nessuna -> serve una regola)
```

Questo e' esattamente il flusso di lavoro per chiudere un **detection gap**: se il test di [Security Assessment / correlazione-eventi](../../Security%20Assessment%20%26%20Hardening/docs/correlazione-eventi.md) non genera l'alert atteso, la causa si trova qui.

---

## Problema 4: La dashboard non mostra dati recenti

**Sintomo:** la UI carica ma i pannelli mostrano solo dati vecchi o vuoti.

**Causa:** e' un guasto tecnico della pipeline a valle (Filebeat -> Indexer -> template/ILM), non un problema di detection.

**Soluzione:** questo caso e' coperto in dettaglio dal troubleshooting tecnico:
- Filebeat non spedisce / template mancante -> [Wazuh / troubleshooting](../Wazuh/docs/troubleshooting.md)
- Indexer giu' / certificati / disco pieno -> [Incident Recovery / Wazuh dashboard](../../Incident%20Recovery%20%26%20Resilience/docs/wazuh-dashboard-recovery.md)

```bash
# Check rapido: arrivano indici di alert recenti?
curl -sk -u admin:admin "https://localhost:9200/_cat/indices/wazuh-alerts-*?v&s=index" | tail -3
```

---

## Problema 5: Gli eventi non si correlano tra loro

**Sintomo:** lo stesso IP attaccante compare in piu' alert separati (SSH, UFW, Cowrie) ma non c'e' una vista unificata dell'attacco.

**Causa:** manca una regola di correlazione/composite che leghi eventi della stessa sorgente-IP in una catena.

**Soluzione:** dal punto di vista dell'analista, correla manualmente e poi automatizza:

```
Workflow di correlazione (dal README del modulo):
  Alert -> Triage (IP noto? interno/esterno?) -> Investigazione (filtra per IP)
        -> Correlazione (stesso IP su SSH+UFW+Cowrie?) -> Risposta (ufw deny / verifica ban)
```

Nella dashboard, filtra Threat Hunting per `data.srcip: <IP>` per vedere tutti gli eventi correlati. Per automatizzare, usa regole composite (`<if_matched_sid>` / `frequency`) come in [alert-fatigue](alert-fatigue.md).

---

## Problema 6: Manca visibilita' su una sorgente (non monitorata)

**Sintomo:** un servizio importante non compare mai negli alert perche' i suoi log non vengono raccolti affatto.

**Causa:** la sorgente non e' configurata come `<localfile>` (per i log su file) o `<command>` (per output di comandi) nell'agent.

**Soluzione:**

```xml
<!-- In /var/ossec/etc/ossec.conf, aggiungi la sorgente mancante -->
<localfile>
  <log_format>json</log_format>
  <location>/percorso/al/log.json</location>
</localfile>
```

```bash
sudo systemctl restart wazuh-agent    # o wazuh-manager se e' l'agent locale 000
```

La mappa completa delle sorgenti che il lab dovrebbe monitorare e' nella tabella "Cosa monitoriamo" del [README del modulo](../README.md).

---

## Comandi utili di verifica

```bash
# Agent connessi e loro stato
sudo /var/ossec/bin/agent_control -l

# Test manuale della pipeline decoder+regole
sudo /var/ossec/bin/wazuh-logtest

# Ultimi alert in tempo reale
sudo tail -f /var/ossec/logs/alerts/alerts.json

# Statistiche: quali regole scattano di piu' (candidati al tuning)
sudo grep -o '"rule":{"level":[0-9]*,"description":"[^"]*"' /var/ossec/logs/alerts/alerts.json | sort | uniq -c | sort -rn | head
```

---

## Collegamenti

- Troubleshooting tecnico di Wazuh (installazione, servizi, certificati) -> [Wazuh / troubleshooting](../Wazuh/docs/troubleshooting.md)
- Dashboard inaccessibile (recovery operativo) -> [Incident Recovery / Wazuh dashboard](../../Incident%20Recovery%20%26%20Resilience/docs/wazuh-dashboard-recovery.md)
- Tuning e riduzione falsi positivi -> [alert-fatigue](alert-fatigue.md)
- Pipeline dei log (6 fasi) -> [log-pipeline](log-pipeline.md)
- Playbook di risposta agli incidenti -> [incident-response](incident-response.md)
