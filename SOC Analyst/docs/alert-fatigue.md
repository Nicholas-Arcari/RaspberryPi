# Alert Fatigue e Tuning: il problema piu' sottovalutato

## Cos'e' l'alert fatigue

L'alert fatigue si verifica quando un analista riceve **troppi alert** (la maggior parte dei quali sono falsi positivi o eventi a bassa priorita'), al punto da iniziare a ignorarli sistematicamente. In un SOC enterprise, un analista L1 puo' ricevere 500-1000+ alert al giorno. Se il 95% sono falsi positivi, la probabilita' che ignori il 5% di veri incidenti e' alta.

**Nel nostro lab** il problema si manifesta in scala ridotta ma reale: Cowrie genera decine di alert per ogni bot che scansiona la porta 2222. Se ogni singolo tentativo di login fallito genera un alert livello 5, la dashboard diventa inutilizzabile in poche ore.

## Strategie di tuning

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
