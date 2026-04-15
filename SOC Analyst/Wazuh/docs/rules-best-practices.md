>  [English](rules-best-practices.en.md) |  **Italiano**

# Wazuh Rules Best Practices: configurazione per il nostro lab

La configurazione di default di Wazuh rileva le minacce più comuni, ma per un home lab esposto a Internet serve un tuning specifico. Queste sono le configurazioni raccomandate per proteggersi da bot, malware, worm e attacchi mirati.

---

## 1. Active Response: blocco automatico degli IP

Active Response è la funzionalità che trasforma Wazuh da "osservatore passivo" a "difensore attivo". Quando un alert raggiunge una certa soglia, Wazuh esegue automaticamente un'azione (tipicamente: bloccare l'IP con iptables/UFW).

Aggiungere a `/var/ossec/etc/ossec.conf` sul Manager:

```xml
<ossec_config>
  <active-response>
    <!-- Blocca IP per 30 minuti dopo 5 tentativi SSH falliti -->
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>5712</rules_id>          <!-- sshd: Multiple auth failures -->
    <timeout>1800</timeout>             <!-- 30 minuti (in secondi) -->
  </active-response>

  <active-response>
    <!-- Blocca IP immediatamente dopo intrusione honeypot -->
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>100012</rules_id>         <!-- Cowrie: Login success -->
    <timeout>86400</timeout>            <!-- 24 ore -->
  </active-response>

  <active-response>
    <!-- Blocca IP dopo scansione porte rilevata -->
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>5710</rules_id>           <!-- Port scan detected -->
    <timeout>3600</timeout>             <!-- 1 ora -->
  </active-response>
</ossec_config>
```

Il comando `firewall-drop` esegue `/var/ossec/active-response/bin/firewall-drop` che aggiunge una regola iptables `DROP` per l'IP. Allo scadere del `timeout`, la regola viene rimossa automaticamente.

**Verifica Active Response in azione:**

```bash
# Mostra gli IP attualmente bloccati da Active Response
sudo /var/ossec/bin/agent_control -L

# Log delle azioni eseguite
sudo tail -f /var/ossec/logs/active-responses.log
```

> **Attenzione:** Non attivare Active Response sulla regola 100011 (login failed honeypot) - bloccheresti i bot prima che rivelino le loro tecniche. L'honeypot deve rimanere accessibile. Blocca solo dopo il login riuscito (100012), quando hai già raccolto le credenziali usate.

---

## 2. Vulnerability Detection: scansione CVE dei pacchetti installati

Wazuh può confrontare i pacchetti installati sul sistema con i database di vulnerabilità note (NVD, Debian Security Tracker) e alertare se un pacchetto ha CVE aperte.

Aggiungere a `ossec.conf` sull'**agent**:

```xml
<wodle name="syscollector">
  <disabled>no</disabled>
  <interval>1h</interval>              <!-- Scansione ogni ora -->
  <scan_on_start>yes</scan_on_start>
  <packages>yes</packages>             <!-- Raccoglie lista pacchetti installati -->
  <ports all="no">yes</ports>          <!-- Raccoglie porte in ascolto -->
  <processes>yes</processes>            <!-- Raccoglie processi attivi -->
</wodle>
```

Sul **Manager**, abilitare il modulo vulnerability detector:

```xml
<vulnerability-detector>
  <enabled>yes</enabled>
  <interval>5m</interval>
  <run_on_start>yes</run_on_start>

  <!-- Feed Debian (il nostro OS) -->
  <provider name="debian">
    <enabled>yes</enabled>
    <os>bookworm</os>
    <update_interval>1h</update_interval>
  </provider>

  <!-- Feed NVD (National Vulnerability Database) -->
  <provider name="nvd">
    <enabled>yes</enabled>
    <update_interval>1h</update_interval>
  </provider>
</vulnerability-detector>
```

Sulla Dashboard, la sezione **Vulnerability Detection** mostrerà i CVE per ogni agent, con severità CVSS, pacchetto affetto e versione da installare.

---

## 3. CDB Lists: IP reputation e IOC (Indicators of Compromise)

Le **CDB lists** (Constant DataBase) permettono di arricchire le regole con liste esterne. L'uso più comune: una lista di IP malevoli noti per generare alert quando compaiono nei log.

```bash
# Scarica una lista di IP noti per attacchi (Abuse.ch)
sudo wget -O /var/ossec/etc/lists/abusech-ipblocklist \
  "https://feodotracker.abuse.ch/downloads/ipblocklist_recommended.txt"

# Converti nel formato CDB (chiave:valore)
sudo awk '{print $1":"}' /var/ossec/etc/lists/abusech-ipblocklist \
  > /var/ossec/etc/lists/abusech-ipblocklist.cdb

# Compila la lista
sudo /var/ossec/bin/wazuh-makelists
```

Aggiungere la lista in `ossec.conf`:

```xml
<ruleset>
  <list>etc/lists/abusech-ipblocklist</list>
</ruleset>
```

Creare una regola che usa la lista in `/var/ossec/etc/rules/local_rules.xml`:

```xml
<!-- Alert quando un IP nella blacklist appare nei log -->
<rule id="100020" level="12">
  <if_sid>5710,5712,100012</if_sid>
  <list field="srcip" lookup="address_match_key">etc/lists/abusech-ipblocklist</list>
  <description>Connessione da IP in blacklist Abuse.ch ($(srcip))</description>
  <mitre>
    <id>T1071</id>  <!-- Application Layer Protocol -->
  </mitre>
</rule>
```

> **Automazione:** Crea un cron job per aggiornare la lista quotidianamente:
> ```bash
> echo "0 6 * * * root wget -qO /var/ossec/etc/lists/abusech-ipblocklist https://feodotracker.abuse.ch/downloads/ipblocklist_recommended.txt && /var/ossec/bin/wazuh-makelists" | sudo tee /etc/cron.d/wazuh-ioc-update
> ```

---

## 4. CIS Benchmark: verifica automatica dell'hardening

Wazuh può verificare automaticamente la conformità del sistema ai **CIS Benchmarks** (Center for Internet Security) - uno standard industriale per l'hardening.

Aggiungere a `ossec.conf` sull'agent:

```xml
<wodle name="sca">
  <enabled>yes</enabled>
  <scan_on_start>yes</scan_on_start>
  <interval>12h</interval>

  <!-- Policy CIS per Debian 12 (Bookworm) -->
  <policies>
    <policy>cis_debian12.yml</policy>
  </policies>
</wodle>
```

Sulla Dashboard, la sezione **Security Configuration Assessment (SCA)** mostrerà:
- Quanti check passano e quanti falliscono
- Per ogni check fallito: cosa correggere e perchè (con riferimento CIS)
- Score complessivo (es. 78/100)

Esempio di check che potrebbe fallire nel nostro setup:

| Check CIS | Stato | Motivo |
|---|---|---|
| "Ensure SSH MaxAuthTries is set to 4 or less" | FAIL | Il nostro `sshd_config` non lo specifica (default: 6) |
| "Ensure permissions on /etc/shadow are configured" | PASS | Permessi corretti (640) |
| "Ensure ip forwarding is disabled" | FAIL | **Atteso**: WireGuard richiede `ip_forward=1` |

> I FAIL "attesi" (come ip forwarding per WireGuard) vanno documentati come eccezioni, non corretti ciecamente. Un buon analista distingue tra un FAIL reale e un FAIL dovuto a un requisito architetturale.
