>  [Italiano](ossec-conf.md) |  **English**

# Deep Dive: ossec.conf - The Heart of Wazuh Configuration

The file `/var/ossec/etc/ossec.conf` controls the behavior of the entire agent/manager. Here are the most important sections with parameter explanations.

---

## `<syscheck>` Section - File Integrity Monitoring

```xml
<syscheck>
  <!-- Interval between full scans (in seconds). 43200 = 12 hours -->
  <frequency>43200</frequency>

  <!-- Calculate SHA-256 hash for every monitored file -->
  <alert_new_files>yes</alert_new_files>

  <!-- Directories to monitor. check_all enables all checks -->
  <directories check_all="yes" realtime="yes">/etc</directories>
  <directories check_all="yes" realtime="yes">/usr/bin</directories>
  <directories check_all="yes" realtime="yes">/usr/sbin</directories>
  <directories check_all="yes">/boot</directories>

  <!-- Files and directories to IGNORE (too noisy) -->
  <ignore>/etc/mtab</ignore>
  <ignore>/etc/resolv.conf</ignore>
  <ignore type="sregex">.log$</ignore>

  <!-- Monitor changes to: hash, permissions, owner, size, timestamp -->
  <check_sha256>yes</check_sha256>
  <check_perm>yes</check_perm>
  <check_owner>yes</check_owner>
  <check_size>yes</check_size>
  <check_mtime>yes</check_mtime>
</syscheck>
```

**Key parameters:**

| Parameter | Meaning | Impact |
|---|---|---|
| `frequency` | Interval between full scans | Lower values = more CPU, faster detection |
| `realtime="yes"` | Uses the kernel's `inotify` for instant detection | Does not wait for periodic scan, but generates more events |
| `check_sha256` | Calculates the SHA-256 hash of each file | If the hash changes, the file has been modified - detects even changes that do not alter the timestamp |
| `alert_new_files` | Generates an alert when a new file appears | Detects malware droppers that create files in `/usr/bin` |
| `ignore` | Excludes files/patterns from monitoring | Essential to reduce false positives (rotating logs, temporary files) |

---

## `<rootcheck>` Section - Rootkit Detection

```xml
<rootcheck>
  <disabled>no</disabled>
  <frequency>43200</frequency>

  <!-- Database of known rootkit signatures -->
  <rootkit_files>/var/ossec/etc/shared/rootkit_files.txt</rootkit_files>
  <rootkit_trojans>/var/ossec/etc/shared/rootkit_trojans.txt</rootkit_trojans>

  <!-- Check for filesystem anomalies (/dev, /proc) -->
  <check_dev>yes</check_dev>
  <check_sys>yes</check_sys>
  <check_pids>yes</check_pids>
  <check_ports>yes</check_ports>

  <!-- Check for hidden files -->
  <check_unixaudit>yes</check_unixaudit>
</rootcheck>
```

`rootcheck` looks for:
- **Known rootkit files** (comparison with signature database)
- **Hidden processes**: compares the output of `/proc` with that of `ps` - if a PID exists in `/proc` but not in `ps`, it could be a rootkit hiding processes
- **Hidden ports**: compares `ss`/`netstat` with `/proc/net/tcp` to find open ports that are not visible
- **Files with anomalous permissions** in `/dev` (a classic rootkit hiding spot)

---

## `<localfile>` Section - Log Sources

```xml
<!-- Authentication log (SSH, sudo, su) -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/auth.log</location>
</localfile>

<!-- Generic system log -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/syslog</location>
</localfile>

<!-- Cowrie honeypot log (JSON format) -->
<localfile>
  <log_format>json</log_format>
  <location>/home/pi/cowrie/var/log/cowrie/cowrie.json</location>
</localfile>

<!-- Docker container log (if mounted on the host) -->
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/docker.log</location>
</localfile>
```

**`log_format` determines the decoder used:**
- `syslog`: standard decoder that extracts timestamp, hostname, program, message
- `json`: JSON decoder that automatically extracts all fields as variables
- `audit`: for `auditd` logs (key=value format)
- `multi-line`: for logs that span multiple lines

---

## Alert Structure in the Indexer (OpenSearch)

Each alert is indexed into an index with the naming pattern `wazuh-alerts-4.x-YYYY.MM.DD`. Here is the complete structure of a document in the index:

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

**Useful fields for threat hunting in the Dashboard:**

| Field | Wazuh Dashboard Query | What You Find |
|---|---|---|
| `rule.id` | `rule.id: 100012` | All honeypot intrusions |
| `rule.level` | `rule.level >= 10` | All critical alerts |
| `data.src_ip` | `data.src_ip: 203.0.113.45` | All events from a specific IP |
| `rule.mitre.id` | `rule.mitre.id: T1078` | All events mapped to a MITRE technique |
| `rule.pci_dss` | `rule.pci_dss: 10.2.5` | All events relevant to PCI DSS compliance |
| `agent.name` | `agent.name: raspberrypi` | All events from a specific agent |
| `rule.firedtimes` | sort by `rule.firedtimes` desc | Rules that fire most often (possible ongoing attack) |
