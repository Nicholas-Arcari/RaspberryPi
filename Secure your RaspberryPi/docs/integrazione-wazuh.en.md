>  [Italiano](integrazione-wazuh.md) |  **English**

# Wazuh Integration Verification - File Integrity Monitoring

If Wazuh is installed (see section [SOC Analyst/Wazuh](../../SOC%20Analyst/Wazuh/README.md)), we can verify that the **Syscheck (File Integrity Monitoring)** module is monitoring the system.

---

## What Is File Integrity Monitoring (FIM)

FIM computes the cryptographic hash (SHA-256) of every file in monitored directories (e.g., `/etc`, `/usr/bin`). Periodically, it recomputes the hashes and compares them. If a file has been modified, created, or deleted, Wazuh generates an alert.

**Why it is critical:** If an attacker modifies `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, or a system binary, Wazuh detects it. This is fundamental for identifying post-exploitation compromises.

---

## Verify That Syscheck Is Running

```bash
sudo /var/ossec/bin/wazuh-control status
```

Look for: `wazuh-syscheckd is running`

---

## Check Syscheck Logs

```bash
sudo tail -f /var/ossec/logs/ossec.log
```

Look for lines such as:

```
wazuh-syscheckd: INFO: Monitoring directory: '/etc'
wazuh-syscheckd: INFO: Monitoring directory: '/usr/bin'
```

---

## Practical Test - Generate a FIM Alert

```bash
# Create a file in a monitored directory
sudo touch /etc/test-wazuh

# Watch the logs
sudo tail -f /var/ossec/logs/ossec.log
```

Within a few minutes (depending on the configured scan interval), you will see a FIM event in the logs. The alert will also appear in the Wazuh Dashboard under **Security Events**.

```bash
# Cleanup after the test
sudo rm /etc/test-wazuh
```

---

## Force an Immediate Rescan

```bash
sudo /var/ossec/bin/wazuh-control restart
```

This forces:

- A new full filesystem scan
- Recomputation of all hashes
- Sending of events to the Manager
