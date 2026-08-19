>  [Italiano](verifica-difese-attive.md) |  **English**

# Runbook 05 - Verifying active defenses

> **When to use this runbook:** you want to be sure that firewall, Fail2ban, SSH hardening, Wazuh FIM, honeypot and segmentation **still actually work** - not just that the services show as "active". To be run after every major update, after a restore, or periodically as a drill.

The key difference from the [post-installation checklist](../../docs/checklist-post-installazione.en.md): that verifies the defenses are **up** (positive state check). This runbook verifies that they **do their job** (effectiveness check), by actively trying to trigger them. It is the "verify, don't trust" approach: an `active` service that blocks nothing is worse than a stopped service, because it gives you a false sense of security.

> **Ethical and safety note:** all the following tests are to be run **only on your own lab**, devices you own. They are defensive checks (control validation), the home version of a purple team. Never point them at third-party networks or systems.

---

## 1. Firewall (UFW): does it really block?

`ufw status: active` is not enough. You must prove that a closed port is actually unreachable and an open one is not, **from another host** on the LAN (not from localhost, which bypasses many rules).

```bash
# From a second device (e.g. your PC), scan the Pi
nmap -Pn -p 22,80,443,53,9443,12345 192.168.0.102
# Expected: only the intended ports open (e.g. 22, 443...).
# A port that should be closed showing as "open" <-- HOLE in the firewall
# Port 12345 (made up) MUST show as filtered/closed -> confirms the default-deny
```

```bash
# On the Pi: are the rules what you think they are?
sudo ufw status numbered
# Compare with the saved baseline (Runbook 08). Extra rules = configuration drift
```

## 2. Fail2ban: does it really ban?

The only way to be sure is to **make it trigger** with controlled failed attempts.

```bash
# From a test host (NOT your IP in ignoreip), generate failed SSH logins:
for i in $(seq 1 6); do ssh -o BatchMode=yes -o ConnectTimeout=3 baduser@192.168.0.102 true 2>/dev/null; done

# On the Pi: did the test IP end up banned?
sudo fail2ban-client status sshd
# Expected: "Banned IP list:" contains the test IP  <-- Fail2ban works

# Clean up after the test
sudo fail2ban-client set sshd unbanip <TEST_IP>
```

If the ban does not trigger: check that the `sshd` jail is `enabled`, that `logpath` points to the right log (`/var/log/auth.log`) and that `maxretry` is consistent.

## 3. SSH hardening: do the directives hold?

```bash
# Password auth must be REFUSED (keys only)
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no pi@192.168.0.102
# Expected: "Permission denied (publickey)" -> password disabled as it should be

# Root login must be refused
ssh root@192.168.0.102
# Expected: refusal -> PermitRootLogin no works

# The effective config (not what you think you wrote)
sudo sshd -T | grep -Ei "permitrootlogin|passwordauthentication|pubkeyauthentication"
# Expected: permitrootlogin no / passwordauthentication no / pubkeyauthentication yes
```

## 4. Kernel hardening: are the sysctls applied?

```bash
sudo sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space net.ipv4.conf.all.rp_filter
# Expected: tcp_syncookies = 1, randomize_va_space = 2, rp_filter = 1
# If a value reverted to default after an update -> the file in /etc/sysctl.d/ is not applied
```

## 5. Wazuh FIM: does it detect the modification of a critical file?

This is the most important test, because FIM (File Integrity Monitoring) is what the [Runbook 06](integrita-post-downtime.en.md) relies on to detect tampering. You must prove it actually triggers.

```bash
# Create/modify a file in a monitored directory (e.g. /etc)
sudo touch /etc/test-fim-$(date +%s).conf

# Wait for the scan cycle (or force it) and look for the alert
# On the Pi (or in the dashboard): syscheck must generate an event
sudo tail -n 50 /var/ossec/logs/alerts/alerts.json | grep -i syscheck
# Expected: an alert with the "path" of the just-created file and a FIM rule (rule id 550/554...)
# Clean up:
sudo rm /etc/test-fim-*.conf
```

If it does not trigger: verify that `/etc` is in `<syscheck>` in `ossec.conf`, and that FIM is in realtime mode or that a scan cycle has passed.

## 6. Detection: do the rules react to an event?

```bash
# Generate an event that must produce an alert (e.g. a failed sudo)
sudo -k ; sudo -S true <<< "wrong-password" 2>/dev/null

# Look for the corresponding alert
sudo tail -n 100 /var/ossec/logs/alerts/alerts.json | grep -i "authentication\|sudo"
# Expected: a failed-authentication alert. Absence -> decoders/rules not active
```

## 7. Honeypot (Cowrie): does it capture and forward to Wazuh?

```bash
# Simulate an attacker entering the honeypot (from your PC)
ssh -o StrictHostKeyChecking=no root@192.168.0.102 -p 2222
# Common passwords like "123456" are accepted by the fake SSH. Type a few commands, then exit.

# 1) Is the event in the Cowrie log?
docker exec cowrie tail -3 /home/cowrie/cowrie-git/var/log/cowrie/cowrie.json
# 2) Did the alert reach Wazuh? (the project's custom rules 100010-100013)
sudo tail -n 100 /var/ossec/logs/alerts/alerts.json | grep -i cowrie
# Expected: the honeypot -> Wazuh chain is intact
```

If the event is in Cowrie but not in Wazuh: the log pipeline is broken -> [Honeypot / log-pipeline](../../Honeypot/docs/log-pipeline.en.md).

## 8. Segmentation (VLAN): does the isolation hold?

Segmentation is worth little if a host on one VLAN can still reach the other. You must prove the isolation.

```bash
# From a host in VLAN 150 (192.168.150.0/24), try to reach the main LAN
ping -c2 192.168.0.102
# Expected (if the segmentation is meant to be watertight): NO reply / blocked
# Reply -> the VLAN is not isolated as you think (inter-VLAN rules too permissive)

# On the Pi: the VLAN interface and the Docker network are the expected ones
ip -br link show end0.150
docker network inspect ipvlan_150 --format '{{.IPAM.Config}}'
```

## 9. Pi-hole: does the sinkhole filter?

```bash
# From a client (not from the host, because of MacVLAN)
dig @192.168.0.250 ads.doubleclick.net +short   # expected 0.0.0.0 (blocked)
dig @192.168.0.250 github.com +short             # expected real IP (not blocked)
```

---

## Scorecard: record the result

Turn the drill into a repeatable artifact. After each run, fill in:

```
DATE: __________
[ ] 1. Firewall: only intended ports open, default-deny confirmed
[ ] 2. Fail2ban: ban triggered on failed logins
[ ] 3. SSH: password/root refused, effective config correct
[ ] 4. Kernel: sysctl hardening applied
[ ] 5. FIM: alert on file modification in /etc
[ ] 6. Detection: alert on auth event
[ ] 7. Honeypot: event propagated Cowrie -> Wazuh
[ ] 8. VLAN: inter-VLAN isolation confirmed
[ ] 9. Pi-hole: sinkhole active
```

A failing check is not a failure of the drill: it is exactly why the drill exists. Document the cause and fix it.

---

## Prevention / cadence

- Run this runbook **after every** OS update, rule change, or restore from backup.
- Automate the non-destructive checks (1, 3, 4, 9) with `scripts/setup.sh verify`; the active tests (2, 5, 6, 7) stay manual and periodic.
- Keep the scorecard under version control: a regression between two drills is a valuable signal.

---

## Links

- Full red-teaming of your own lab -> [Security Assessment & Hardening](../../Security%20Assessment%20%26%20Hardening/)
- Detecting a compromise that already happened -> [Runbook 06: post-downtime integrity](integrita-post-downtime.en.md)
- Baseline and state checklist -> [post-installation checklist](../../docs/checklist-post-installazione.en.md)
