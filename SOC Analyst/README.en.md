>  [Italiano](README.md) |  **English**

# SOC Analyst - Security Operations Center

This section contains the tools and configurations related to centralized security monitoring - the heart of a SOC (Security Operations Center), even at a "home lab" scale.

---

## What we monitor

| Source | What it generates | Alert type |
|---|---|---|
| SSH (auth.log) | Failed/successful login attempts | Brute force, unauthorized access |
| Fail2ban | Automatic IP bans | Ongoing automated attacks |
| UFW (firewall) | Blocked/allowed connections | Port scans, anomalous traffic |
| Cowrie (Honeypot) | Intrusions, executed commands, credentials | Active attackers on the network |
| Syscheck (FIM) | System file modifications | Post-exploitation compromise |
| Docker | Container logs, errors | Malfunctions, escape attempts |

---

## Documentation index

| Document | Content |
|---|---|
| [What is a SOC and SOC Tiers](docs/tier-soc.en.md) | SOC definition, L1/L2/L3 roles with responsibilities, required skills, and application in our lab |
| [Log Pipeline](docs/log-pipeline.en.md) | The 6 phases of the data flow (collection, decoding, rules, enrichment, indexing, visualization) and diagnostic table |
| [Alert Fatigue and Tuning](docs/alert-fatigue.en.md) | Tuning strategies: severity levels, syscheck exclusions, aggregation with composite rules, XML examples |
| [SIEM Comparison: Wazuh vs Splunk](docs/confronto-siem.en.md) | Architectural comparison, reasons for our choice, migration path to Splunk, equivalent configurations |
| [Incident Response Playbook](docs/incident-response.en.md) | NIST SP 800-61 framework, 3 operational playbooks (honeypot, SSH brute force, FIM), escalation matrix |

---

## Tools

### Wazuh SIEM/XDR

The primary platform. Detailed installation and configuration in the dedicated sub-section:

**[Wazuh - Installation and Configuration](./Wazuh/README.en.md)**

---

## Typical analysis workflow (for our lab)

1. **Alert** appears on the Wazuh dashboard (e.g. "Cowrie: SUCCESSFUL INTRUSION")
2. **Triage**: check the source IP - is it a known bot? Is it from the local network or the Internet?
3. **Investigation**: in the Threat Hunting section, filter by that IP and view all correlated events
4. **Correlation**: did the IP also attempt to access real SSH (port 22)? Did it trigger firewall rules?
5. **Response**: if the IP is suspicious, manually block it on UFW (`sudo ufw deny from <IP>`) or verify that Fail2ban has already banned it
6. **Documentation**: record the incident for future reference

This is the workflow of a SOC analyst, scaled down for a home lab but conceptually identical to the enterprise one.
