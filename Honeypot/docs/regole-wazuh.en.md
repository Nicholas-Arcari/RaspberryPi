>  [Italiano](regole-wazuh.md) |  **English**

# Custom Wazuh Rules

Wazuh's default rules do not cover Cowrie-specific events. I had to create custom rules to generate alerts on the dashboard.

## File: `/var/ossec/etc/rules/local_rules.xml`

```xml
<group name="local,syslog,sshd,">

  <!-- Regola base: cattura QUALSIASI evento Cowrie -->
  <rule id="100010" level="3">
    <decoded_as>json</decoded_as>
    <field name="eventid" type="pcre2">^cowrie\.</field>
    <description>Cowrie: Attività generica Honeypot rilevata</description>
  </rule>

  <!-- Tentativo di login fallito (Brute Force) -->
  <rule id="100011" level="5">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.login.failed</field>
    <description>Cowrie: Tentativo di accesso fallito (Brute Force)</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <!-- Login riuscito - CRITICO: un attaccante è "dentro" l'honeypot -->
  <rule id="100012" level="10">
    <if_sid>100010</if_sid>
    <field name="eventid">cowrie.login.success</field>
    <description>Cowrie: INTRUSIONE RIUSCITA - Un attaccante è entrato nell'Honeypot</description>
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

## Rule Explanation

**Hierarchical structure:** Rule `100010` is the parent rule that catches any Cowrie event (the `eventid` field starts with `cowrie.`). The child rules (`100011-100013`) use `<if_sid>100010</if_sid>` to fire only if the parent rule matched -- this avoids rewriting the JSON condition in every rule.

**Alert levels (level):**

| Level | Meaning | Suggested Action |
|---|---|---|
| 3 | Informational | Silent log |
| 5 | Warning | Notify if configured |
| 7 | Notable | Investigate |
| 10 | Critical | Immediate action |

**MITRE tag `<id>T1078</id>`:** Associates the alert with the MITRE ATT&CK technique "Valid Accounts." This allows filtering alerts by technique in the Wazuh dashboard and correlating with other events.

**PCI DSS tags:** `pci_dss_10.2.4` and `pci_dss_10.2.5` map to PCI DSS requirements for logging failed and successful access attempts. Useful if the project is presented in a compliance context.

## Real-World Cowrie JSON Log Example

Each event written by Cowrie to `cowrie.json` has this structure. Here is a successful login:

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

Key field explanation:

| Field | Meaning | Threat Hunting Value |
|---|---|---|
| `eventid` | Cowrie event type | Discriminator for Wazuh rules (`login.success`, `login.failed`, `command.input`) |
| `username` / `password` | Credentials tried by the attacker | Pattern analysis: if they try `admin/admin` it is a bot; if they try specific credentials it could be targeted |
| `src_ip` | Attacker IP | Correlation with other events: did the same IP also probe the real port 22? |
| `src_port` | Source port (ephemeral) | Sequential ports suggest an automated scanner |
| `session` | Unique session ID | Allows reconstructing the attacker's entire session (all commands) |
| `protocol` | SSH or Telnet | Telnet is a signal of very old bots or IoT malware (Mirai-like) |

And here is a post-intrusion command execution event:

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

The `input` field contains the exact command typed. Commands like `cat /etc/shadow`, `wget`, `curl`, `chmod +x` are indicators of active post-exploitation.
