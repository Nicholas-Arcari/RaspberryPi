# Regole Custom per Wazuh

Le regole di default di Wazuh non coprono gli eventi specifici di Cowrie. Ho dovuto creare regole personalizzate per generare alert sulla dashboard.

## File: `/var/ossec/etc/rules/local_rules.xml`

```xml
<group name="local,syslog,sshd,">

  <!-- Regola base: cattura QUALSIASI evento Cowrie -->
  <rule id="100010" level="3">
    <decoded_as>json</decoded_as>
    <field name="eventid" type="pcre2">^cowrie\.</field>
    <description>Cowrie: Attivita' generica Honeypot rilevata</description>
  </rule>

  <!-- Tentativo di login fallito (Brute Force) -->
  <rule id="100011" level="5">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.login.failed</field>
    <description>Cowrie: Tentativo di accesso fallito (Brute Force)</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <!-- Login riuscito - CRITICO: un attaccante e' "dentro" l'honeypot -->
  <rule id="100012" level="10">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.login.success</field>
    <description>Cowrie: INTRUSIONE RIUSCITA - Un attaccante e' entrato nell'Honeypot</description>
    <mitre>
      <id>T1078</id>  <!-- Valid Accounts -->
    </mitre>
    <group>authentication_success,pci_dss_10.2.5,</group>
  </rule>

  <!-- Esecuzione comandi - l'attaccante sta esplorando -->
  <rule id="100013" level="7">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.command.input</field>
    <description>Cowrie: L'attaccante ha digitato un comando nell'Honeypot</description>
  </rule>

</group>
```

## Spiegazione delle regole

**Struttura gerarchica:** La regola `100010` e' la regola padre che cattura qualsiasi evento Cowrie (il campo `eventid` inizia con `cowrie.`). Le regole figlie (`100011-100013`) usano `<if_sid>100010</if_sid>` per attivarsi solo se la regola padre ha fatto match - questo evita di riscrivere la condizione JSON in ogni regola.

**Livelli di allarme (level):**

| Level | Significato | Azione suggerita |
|---|---|---|
| 3 | Informativo | Log silenzioso |
| 5 | Attenzione | Notifica se configurata |
| 7 | Rilevante | Investigare |
| 10 | Critico | Azione immediata |

**Tag MITRE `<id>T1078</id>`:** Associa l'alert alla tecnica MITRE ATT&CK "Valid Accounts". Questo permette di filtrare gli alert per tecnica nella dashboard Wazuh e di correlare con altri eventi.

**Tag PCI DSS:** `pci_dss_10.2.4` e `pci_dss_10.2.5` mappano i requisiti PCI DSS per il logging degli accessi falliti e riusciti. Utile se il progetto viene presentato in contesto compliance.

## Esempio reale di log JSON Cowrie

Ogni evento scritto da Cowrie in `cowrie.json` ha questa struttura. Ecco un login riuscito:

```json
{
  "eventid": "cowrie.login.success",
  "username": "root",
  "password": "12345",
  "message": "login attempt [root/12345] succeeded",
  "sensor": "cowrie-nas",
  "timestamp": "2026-03-15T14:32:07.892451Z",
  "src_ip": "203.0.113.45",
  "src_port": 48291,
  "dst_ip": "192.168.0.102",
  "dst_port": 2222,
  "session": "a]8f2e1c4b5d",
  "protocol": "ssh",
  "system": "SSHTransport,1,203.0.113.45"
}
```

Spiegazione dei campi chiave:

| Campo | Significato | Valore per threat hunting |
|---|---|---|
| `eventid` | Tipo di evento Cowrie | Discriminatore per le regole Wazuh (`login.success`, `login.failed`, `command.input`) |
| `username` / `password` | Credenziali provate dall'attaccante | Pattern analysis: se prova `admin/admin` e' un bot; se prova credenziali specifiche potrebbe essere targeted |
| `src_ip` | IP dell'attaccante | Correlazione con altri eventi: lo stesso IP ha provato anche la porta 22 reale? |
| `src_port` | Porta sorgente (effimera) | Porte sequenziali suggeriscono uno scanner automatizzato |
| `session` | ID univoco della sessione | Permette di ricostruire l'intera sessione dell'attaccante (tutti i comandi) |
| `protocol` | SSH o Telnet | Telnet e' un segnale di bot molto vecchi o IoT malware (Mirai-like) |

Ed ecco un evento di esecuzione comando post-intrusione:

```json
{
  "eventid": "cowrie.command.input",
  "input": "cat /etc/shadow",
  "message": "CMD: cat /etc/shadow",
  "sensor": "cowrie-nas",
  "timestamp": "2026-03-15T14:32:45.123456Z",
  "src_ip": "203.0.113.45",
  "session": "a]8f2e1c4b5d"
}
```

Il campo `input` contiene il comando esatto digitato. Comandi come `cat /etc/shadow`, `wget`, `curl`, `chmod +x` sono indicatori di post-exploitation attiva.
