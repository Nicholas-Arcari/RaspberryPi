>  [Italiano](troubleshooting.md) |  **English**

# Troubleshooting - Security Assessment: real problems and solutions

> Problems that arise when the **test itself** does not work or produces misleading results: scans showing wrong ports, the honeypot skewing the brute force, Fail2ban banning your test IP, the attack not generating the expected alert, CGNAT preventing the external test. It is the troubleshooting of red-teaming your own lab.

> **Ethical and authorization note:** all the techniques described here are to be used **only** against your own lab, devices you own. It is an authorized self-assessment. Never against third-party systems or networks.

---

## Problem 1: Nmap shows misleading results (host "down" or ports "filtered")

**Symptom:** Nmap reports the host as down, or all ports as `filtered`, even though you know the services are active.

**Cause:** three typical causes. (1) The SYN scan (`-sS`) requires **root** privileges. (2) The firewall drops the ICMP probes and Nmap concludes the host is down. (3) UFW's rate-limiting/deny makes open ports appear `filtered`.

**Solution:**

```bash
# SYN scan + version detection, skipping ping discovery (-Pn), with privileges
sudo nmap -sS -sV -Pn 192.168.0.102
#   -sS  : SYN scan (needs root)
#   -sV  : version detection on the services
#   -Pn  : do NOT do ICMP host discovery (the host is considered up regardless)

# If a port shows as "filtered" it is a good sign: the firewall is dropping it as it should.
# Compare with the expected surface (only the forwarded ports seen from OUTSIDE).
```

The scan rationale and the line-by-line analysis are in [reconnaissance](reconnaissance.en.md).

---

## Problem 2: The brute force "succeeds" against any password (false positive)

**Symptom:** you launch Hydra on port 2222 and it seems that ALL credentials work: an apparently successful brute force.

**Cause:** **you are not hitting the real SSH, but the Cowrie honeypot** (port 2222/2223). Cowrie deliberately accepts common credentials to record the attacker. A "success" there is not a flaw: it is the trap working.

**Solution:** always distinguish the target.

```bash
# 22  = REAL SSH (hardened: key only, no password, no root)  -> must RESIST
# 2222= Cowrie honeypot (pretends to give in)                -> "success" expected and intended

# Verify the real SSH (22) resists the password brute force:
hydra -l pi -P password-list.txt ssh://192.168.0.102 -t 4
#   Expected: NO success (password auth disabled). A success here = a real flaw.
```

The rationale (Hydra, honeypot vs real service, pivot risk) is in [exploitation](exploitation.en.md).

---

## Problem 3: Fail2ban bans MY IP during the brute-force test

**Symptom:** after a few attempts, Hydra stalls and you can no longer reach the host: you banned yourself.

**Cause:** the test brute force exceeded `maxretry` and Fail2ban banned your IP - exactly what it must do with an attacker. But during an authorized test it is a self-DoS.

**Solution:**

```bash
# During the test, temporarily exempt your IP (then REMOVE the exemption)
sudo fail2ban-client set sshd unbanip 192.168.0.50
# or add your IP to ignoreip in jail.local only for the duration of the test

# After the test, restore full protection and verify the ban ACTUALLY triggers
# against a non-exempt IP (this is the positive test of Runbook 05).
```

> This is also an assessment result: having confirmed that Fail2ban bans under brute force is a validated defense, not a hiccup. See [Incident Recovery / verifying defenses, sec.2](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.en.md).

---

## Problem 4: The test attack did NOT generate the expected Wazuh alert

**Symptom:** you ran an attack (scan, brute force, honeypot intrusion) but the corresponding alert does not appear in the Wazuh dashboard. It is the most important result not to ignore: a **detection gap**.

**Cause:** the event log does not reach the manager, no decoder/rule interprets it, or the agent is disconnected.

**Solution:**

```bash
# 1. Is the agent that should have seen the event connected?
sudo /var/ossec/bin/agent_control -l

# 2. Does the event produce an alert if fed to the rule engine?
sudo /var/ossec/bin/wazuh-logtest      # paste a real log line of the attack
```

A detection gap discovered during the assessment is a valuable finding: it means that attack, if real, would go unnoticed. The full decoder/rule diagnosis is in [SOC Analyst / troubleshooting, Problem 3](../../SOC%20Analyst/docs/troubleshooting.en.md); the expected end-to-end correlation is in [correlazione-eventi](correlazione-eventi.en.md).

---

## Problem 5: The Wazuh agent disconnected during the test

**Symptom:** during the assessment, events stop reaching the SIEM; the agent shows as `Disconnected`.

**Cause:** your own test (or a firewall rule applied during remediation) interrupted the agent-manager connection (ports 1514/1515), or the agent errored out.

**Solution:**

```bash
sudo /var/ossec/bin/agent_control -l           # status of all agents
# On the agent: check connectivity to the manager
sudo /var/ossec/bin/agent_control -i <id>
# Make sure UFW allows 1514/1515 between agent and manager
sudo ufw status | grep -E "1514|1515"
sudo systemctl restart wazuh-agent
```

> Watch the UFW rule order during remediation: a too-broad `deny` can cut the agent off from the manager. It is a documented "agent disconnected" case in [remediation](remediation.en.md).

---

## Problem 6: I can't test from the outside (CGNAT)

**Symptom:** you want to simulate an attacker from the Internet, but from outside you cannot reach any service, not even the forwarded ones.

**Cause:** the FWA uplink is behind **CGNAT**: you do not have a routable public IP, so a test "from outside" towards your IP does not arrive. It is not a lab problem, it is the provider's architecture.

**Solution:** for a realistic external test you need an outbound channel:

```bash
# Temporarily expose the service to test via an outbound tunnel (e.g. Ngrok),
# launch the test against the tunnel endpoint, then CLOSE the tunnel.
# Alternatively, test from inside the LAN accepting that it does not replicate the external view.
```

The CGNAT + Ngrok context for controlled exposure is in [remediation](remediation.en.md) and in the runbook [Incident Recovery / VPN and containers, A.3](../../Incident%20Recovery%20%26%20Resilience/docs/vpn-e-container-recovery.en.md).

---

## Problem 7: A UFW remediation rule does not have the intended effect

**Symptom:** after fixing a vulnerability with a UFW rule, the service stays reachable or, worse, something else broke.

**Cause:** the **order** of the UFW rules is critical: the first match wins. A generic `allow` before a specific `deny` cancels the latter.

**Solution:**

```bash
sudo ufw status numbered           # real evaluation order
sudo ufw insert 1 deny from <IP>   # insert in the correct position
```

Detail of the critical rule order and the table of fixed vulnerabilities in [remediation](remediation.en.md); the UFW/netfilter mapping in [Secure your RaspberryPi / firewall-ufw](../../Secure%20your%20RaspberryPi/docs/firewall-ufw.en.md).

---

## Useful verification commands

```bash
# Real attack surface (run from a SECOND LAN host)
sudo nmap -sS -sV -Pn 192.168.0.102

# Does the real SSH resist the password brute force?
hydra -l pi -P /usr/share/wordlists/rockyou.txt ssh://192.168.0.102 -t 4   # expected: 0 successes

# Does the attack generate the expected alert?
sudo /var/ossec/bin/wazuh-logtest
sudo tail -f /var/ossec/logs/alerts/alerts.json
```

---

## Links

- Detection gap diagnosis (decoder/rules) -> [SOC Analyst / troubleshooting](../../SOC%20Analyst/docs/troubleshooting.en.md)
- Actively validating the defenses (firewall, Fail2ban, FIM) -> [Incident Recovery / verifying active defenses](../../Incident%20Recovery%20%26%20Resilience/docs/verifica-difese-attive.en.md)
- Scan and reconnaissance -> [reconnaissance](reconnaissance.en.md); exploitation -> [exploitation](exploitation.en.md); remediation -> [remediation](remediation.en.md)
- Event correlation and end-to-end test -> [correlazione-eventi](correlazione-eventi.en.md); STRIDE model -> [threat-model](threat-model.en.md)
