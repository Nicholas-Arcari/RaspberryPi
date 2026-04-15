>  [Italiano](incident-response.md) |  **English**

# Incident Response Playbook

This playbook defines **what to do concretely** when Wazuh generates a critical alert. It follows the NIST SP 800-61 framework (Computer Security Incident Handling Guide), adapted to our home lab.

## The 6 phases of Incident Response

```
[1] Preparation → [2] Identification → [3] Containment → [4] Eradication → [5] Recovery → [6] Lessons Learned
        │                   │                    │                   │                │                │
   Tools ready         "Is this a real       Limit the          Remove the        Restore           What to improve
   Contacts defined     incident?"           damage NOW         root cause        the service       for next time
   Playbook written
```

## Playbook 1: Honeypot Intrusion (alert rule 100012, level 10)

**Trigger:** Wazuh alert "Cowrie: Login success detected on honeypot"

**Phase 1 - Identification (5 minutes)**

```bash
# 1. Read the alert on the Dashboard or from the logs
sudo tail -20 /var/ossec/logs/alerts/alerts.json | python3 -m json.tool | grep -A5 "cowrie"

# 2. Extract the attacker's source IP
# From the Dashboard: Threat Hunting → filter "rule.id: 100012" → field data.cowrie.src_ip

# 3. Verify if the IP is a known bot
# Search at https://www.abuseipdb.com/check/<IP>
# Or from the terminal:
curl -s "https://api.abuseipdb.com/api/v2/check?ipAddress=<IP>" \
  -H "Key: <YOUR_API_KEY>" -H "Accept: application/json" | python3 -m json.tool
```

**Decision:** Is the IP an automated bot (confidence score > 80% on AbuseIPDB) or a targeted attack (never-before-seen IP, sophisticated commands)?

**Phase 2 - Containment (10 minutes)**

```bash
# 4. IMMEDIATE: block the IP on the firewall
sudo ufw deny from <ATTACKER_IP> comment "Honeypot intrusion - $(date +%Y-%m-%d)"

# 5. Verify that the attacker did NOT reach the real host
# Check the system's SSH logs (port 22, not 2222)
grep "<ATTACKER_IP>" /var/log/auth.log

# 6. Verify there are no active connections from the IP
ss -tn | grep "<ATTACKER_IP>"

# 7. Check that the Cowrie container is still intact
docker inspect cowrie --format '{{.State.Status}}'  # Must be "running"
docker logs cowrie --tail 20                         # Look for anomalous errors
```

**Phase 3 - Eradication (15 minutes)**

```bash
# 8. Analyze the complete session on the Dashboard
#    Filter: data.cowrie.src_ip: "<ATTACKER_IP>"
#    Sort by ascending timestamp
#    Look for: executed commands, downloaded files, escape attempts

# 9. If the attacker downloaded files into the honeypot, capture them for analysis
docker exec cowrie ls -la /home/cowrie/cowrie-git/var/lib/cowrie/downloads/
# Files downloaded by the attacker are saved here with SHA-256 hash as filename

# 10. If you suspect container escape (anomalous events in host logs):
# Check for suspicious processes
ps auxf | grep -v grep | grep -E "(nc|ncat|bash -i|python.*socket)"
# Check for anomalous network connections
ss -tlnp | grep -v -E "(sshd|docker|wazuh|filebeat)"
# Check for recently modified files in critical directories
find /etc /usr/bin /usr/sbin -mmin -30 -ls 2>/dev/null
```

**Phase 4 - Recovery**

```bash
# 11. If the container is compromised, recreate it from scratch (data is in the volume)
docker stop cowrie && docker rm cowrie
docker pull cowrie/cowrie:latest
# Recreate with the same docker-compose

# 12. Verify that Wazuh is still ingesting the logs
sudo /var/ossec/bin/wazuh-logtest
# Paste a Cowrie log line and verify that the rule matches
```

**Phase 5 - Lessons Learned**

After the incident, answer these questions:
- Did the alert arrive in time? If not, is a rule with a higher frequency needed?
- Did the firewall block the IP fast enough? Is an automatic rule needed?
- Did the attacker use techniques not covered by the Wazuh rules? Is a new custom rule needed?

## Playbook 2: Brute force on real SSH (alert rule 5712, level 10)

**Trigger:** Wazuh alert "sshd: Multiple authentication failures"

**This is more serious than the honeypot** - the attacker is hitting the real SSH service (port 22), not the trap.

```bash
# 1. IMMEDIATE: verify that Fail2ban has already banned the IP
sudo fail2ban-client status sshd | grep "<IP>"

# 2. If not banned, block manually
sudo ufw deny from <ATTACKER_IP> comment "SSH brute force - $(date +%Y-%m-%d)"

# 3. Verify that NO login succeeded
grep "Accepted" /var/log/auth.log | grep "<ATTACKER_IP>"
# If you find results: IMMEDIATE ESCALATION - the attacker is inside

# 4. If the login succeeded (worst case):
#    a. Identify the compromised user
#    b. Lock the user: sudo passwd -l <user>
#    c. Terminate active sessions: sudo pkill -u <user>
#    d. Change ALL passwords and regenerate SSH keys
#    e. Check the user's crontab and authorized_keys for persistence
sudo crontab -l -u <user>
cat /home/<user>/.ssh/authorized_keys   # Look for unknown keys
#    f. Start an immediate FIM scan: sudo /var/ossec/bin/wazuh-control restart
```

## Playbook 3: System file modification (alert rule 550-554, FIM)

**Trigger:** Wazuh alert "File modified" on `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config` or binaries in `/usr/bin`

```bash
# 1. Identify WHAT changed
# From the Dashboard: field syscheck.path, syscheck.diff (if enabled)

# 2. Identify WHO changed the file
# Field syscheck.audit.user.name (requires auditd)
# Or: check auth.log for recent sudo commands
grep "sudo" /var/log/auth.log | tail -20

# 3. Is the change legitimate?
#    - Did you just run apt upgrade? → normal
#    - Did you modify sshd_config via OMV? → normal
#    - Nobody touched the system? → INVESTIGATE

# 4. If illegitimate:
#    a. Save the modified file for forensic analysis
sudo cp /etc/<modified_file> /tmp/evidence_$(date +%Y%m%d)
#    b. Restore from backup or from the package
sudo apt install --reinstall <package_that_contains_the_file>
#    c. Check if the attacker created a backdoor
sudo grep -r "0:0" /etc/passwd    # Look for users with UID 0 (root) that are not legitimate
sudo find / -perm -4000 -ls 2>/dev/null   # Look for new SUID binaries
```

## Escalation matrix

| Alert level | Type | Action | Response time |
|---|---|---|---|
| 3-5 | Info/Low | Log it, review at end of day | 24 hours |
| 6-9 | Medium | Investigate within 1 hour, correlate with other events | 1 hour |
| 10-12 | High | Immediate containment (block IP/user), full investigation | 15 minutes |
| 13-15 | Critical | All inbound traffic blocked, forensic analysis, consider disconnecting the Pi from the network | Immediate |

> **Operational rule:** A playbook that has not been tested does not work. At least once a month, simulate an incident (connect to the honeypot from an external network, modify a monitored file) and follow the playbook from start to finish. Every time you will find steps that are missing or that do not work as expected.
