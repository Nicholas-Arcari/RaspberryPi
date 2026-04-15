>  [English](ossec-conf.en.md) |  **Italiano**

# Deep Dive: ossec.conf - il cuore della configurazione Wazuh

Il file `/var/ossec/etc/ossec.conf` controlla il comportamento dell'intero agente/manager. Ecco le sezioni più importanti con spiegazione dei parametri.

---

## Sezione `<syscheck>` - File Integrity Monitoring

```xml
<syscheck>
  <!-- Intervallo tra scan completi (in secondi). 43200 = 12 ore -->
  <frequency>43200</frequency>

  <!-- Calcola hash SHA-256 per ogni file monitorato -->
  <alert_new_files>yes</alert_new_files>

  <!-- Directory da monitorare. check_all abilita tutti i controlli -->
  <directories check_all="yes" realtime="yes">/etc</directories>
  <directories check_all="yes" realtime="yes">/usr/bin</directories>
  <directories check_all="yes" realtime="yes">/usr/sbin</directories>
  <directories check_all="yes">/boot</directories>

  <!-- File e directory da IGNORARE (troppo rumorosi) -->
  <ignore>/etc/mtab</ignore>
  <ignore>/etc/resolv.conf</ignore>
  <ignore type="sregex">.log$</ignore>

  <!-- Monitora cambiamenti di: hash, permessi, owner, size, timestamp -->
  <check_sha256>yes</check_sha256>
  <check_perm>yes</check_perm>
  <check_owner>yes</check_owner>
  <check_size>yes</check_size>
  <check_mtime>yes</check_mtime>
</syscheck>
```

**Parametri chiave:**

| Parametro | Significato | Impatto |
|---|---|---|
| `frequency` | Intervallo tra scan completi | Valori bassi = più CPU, rilevamento più rapido |
| `realtime="yes"` | Usa `inotify` del kernel per rilevamento istantaneo | Non aspetta lo scan periodico, ma genera più eventi |
| `check_sha256` | Calcola hash SHA-256 di ogni file | Se l'hash cambia, il file è stato modificato - rileva anche modifiche che non cambiano timestamp |
| `alert_new_files` | Genera alert quando un file nuovo appare | Rileva dropper di malware che creano file in `/usr/bin` |
| `ignore` | Esclude file/pattern dal monitoraggio | Essenziale per ridurre i falsi positivi (log che ruotano, file temporanei) |

---

## Sezione `<rootcheck>` - Rilevamento rootkit

```xml
<rootcheck>
  <disabled>no</disabled>
  <frequency>43200</frequency>

  <!-- Database di signature rootkit noti -->
  <rootkit_files>/var/ossec/etc/shared/rootkit_files.txt</rootkit_files>
  <rootkit_trojans>/var/ossec/etc/shared/rootkit_trojans.txt</rootkit_trojans>

  <!-- Controlla anomalie nel filesystem (/dev, /proc) -->
  <check_dev>yes</check_dev>
  <check_sys>yes</check_sys>
  <check_pids>yes</check_pids>
  <check_ports>yes</check_ports>

  <!-- Controlla file nascosti -->
  <check_unixaudit>yes</check_unixaudit>
</rootcheck>
```

`rootcheck` cerca:
- **File noti di rootkit** (confronto con database di signature)
- **Processi nascosti**: confronta l'output di `/proc` con quello di `ps` - se un PID esiste in `/proc` ma non in `ps`, potrebbe essere un rootkit che nasconde processi
- **Porte nascoste**: confronta `ss`/`netstat` con `/proc/net/tcp` per trovare porte aperte non visibili
- **File con permessi anomali** in `/dev` (un classico nascondiglio per rootkit)

---

## Sezione `<localfile>` - Sorgenti di log

```xml
<!-- Log di autenticazione (SSH, sudo, su) -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/auth.log</location>
</localfile>

<!-- Log di sistema generico -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/syslog</location>
</localfile>

<!-- Log Cowrie honeypot (formato JSON) -->
<localfile>
  <log_format>json</log_format>
  <location>/home/pi/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>

<!-- Log Docker container (se montati sull'host) -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/docker.log</location>
</localfile>
```

**`log_format` determina il decoder usato:**
- `syslog`: decoder standard che estrae timestamp, hostname, program, message
- `json`: decoder JSON che estrae automaticamente tutti i campi come variabili
- `audit`: per log di `auditd` (formato key=value)
- `multi-line`: per log che si estendono su più righe

---

## Struttura di un alert nell'Indexer (OpenSearch)

Ogni alert viene indicizzato in un indice con naming pattern `wazuh-alerts-4.x-YYYY.MM.DD`. Ecco la struttura completa di un documento nell'indice:

```json
{
  "_index": "wazuh-alerts-4.x-2026.03.15",
  "_id": "a1b2c3d4e5f6",
  "_source": {
    "timestamp": "2026-03-15T14:32:07.892+0000",
    "rule": {
      "level": 10,
      "description": "Cowrie: INTRUSIONE RIUSCITA",
      "id": "100012",
      "mitre": {
        "id": ["T1078"],
        "tactic": ["Initial Access"],
        "technique": ["Valid Accounts"]
      },
      "firedtimes": 3,
      "mail": false,
      "groups": ["local", "syslog", "sshd", "authentication_success"],
      "pci_dss": ["10.2.5"],
      "gdpr": ["IV_32.2"]
    },
    "agent": {
      "id": "000",
      "name": "raspberrypi",
      "ip": "127.0.0.1"
    },
    "manager": {
      "name": "raspberrypi"
    },
    "data": {
      "eventid": "cowrie.login.success",
      "username": "root",
      "password": "12345",
      "src_ip": "203.0.113.45",
      "src_port": "48291",
      "dst_ip": "192.168.0.102",
      "dst_port": "2222",
      "session": "a8f2e1c4b5d",
      "protocol": "ssh"
    },
    "decoder": {
      "name": "json"
    },
    "location": "/home/pi/cowrie/var/log/cowrie/cowrie.json"
  }
}
```

**Campi utili per il threat hunting sulla Dashboard:**

| Campo | Query Wazuh Dashboard | Cosa trovi |
|---|---|---|
| `rule.id` | `rule.id: 100012` | Tutte le intrusioni nell'honeypot |
| `rule.level` | `rule.level >= 10` | Tutti gli alert critici |
| `data.src_ip` | `data.src_ip: 203.0.113.45` | Tutti gli eventi da un IP specifico |
| `rule.mitre.id` | `rule.mitre.id: T1078` | Tutti gli eventi mappati a una tecnica MITRE |
| `rule.pci_dss` | `rule.pci_dss: 10.2.5` | Tutti gli eventi rilevanti per PCI DSS compliance |
| `agent.name` | `agent.name: raspberrypi` | Tutti gli eventi da un agente specifico |
| `rule.firedtimes` | ordina per `rule.firedtimes` desc | Regole che si attivano più spesso (possibile attacco in corso) |
