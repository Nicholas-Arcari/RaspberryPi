>  [Italiano](tier-soc.md) |  **English**

# What is a SOC

A SOC is the nerve center of an organization's security operations. Its mission is to **detect, analyze, and respond** to security incidents in real time.

In an enterprise, a SOC is composed of:

- **People**: Level 1 analysts (triage), Level 2 (investigation), Level 3 (threat hunting)
- **Processes**: incident response playbooks, escalation, communication
- **Technology**: SIEM (log collection and correlation), SOAR (response automation), EDR (endpoint protection)

In our home lab, we recreate the technology component using **Wazuh** as an open-source SIEM/XDR, integrated with all of the Raspberry Pi's services.

---

## SOC Tiers: roles and responsibilities

In an enterprise SOC, analysts are organized into tiers with increasing responsibilities. In our home lab we fill all the roles ourselves, but understanding the distinction is fundamental for anyone looking to work in the field.

### L1 - Triage Analyst

| Aspect | Detail |
|---|---|
| **Primary responsibility** | Continuous alert monitoring and first-level filtering |
| **Typical activities** | Classify alerts (true/false positive), open tickets, apply predefined playbooks |
| **Key decision** | "Is this alert a real incident or background noise?" |
| **Required skills** | Log reading, knowledge of SIEM rules, familiarity with MITRE ATT&CK |
| **Average time per alert** | 5-15 minutes |
| **Escalation** | If the alert requires in-depth investigation -> escalate to L2 |

**In our lab**: when an alert appears on the Wazuh dashboard (e.g. "Cowrie: Login success"), the L1 work consists of checking the source IP, verifying if it is a known bot (by consulting threat intelligence such as AbuseIPDB), and deciding whether action is required.

### L2 - Incident Responder

| Aspect | Detail |
|---|---|
| **Primary responsibility** | In-depth investigation of incidents escalated from L1 |
| **Typical activities** | Event correlation from multiple sources, initial forensic analysis, incident containment |
| **Key decision** | "What is the extent of the compromise and how do we contain it?" |
| **Required skills** | Threat hunting, network analysis (Wireshark/tcpdump), scripting (Python/Bash), basic forensics |
| **Average time per incident** | 1-8 hours |
| **Escalation** | If the threat is advanced (APT, zero-day) -> escalate to L3 |

**In our lab**: after L1 identifies a suspicious IP, the L2 work consists of searching for all correlated events (firewall, honeypot, SSH) to reconstruct the attacker's complete kill chain, as documented in the [Security Assessment](../../Security%20Assessment%20%26%20Hardening/README.en.md) section.

### L3 - Threat Hunter / Senior Analyst

| Aspect | Detail |
|---|---|
| **Primary responsibility** | Proactive hunting for threats not detected by automated alerts |
| **Typical activities** | Custom rule creation, SIEM tuning, malware analysis, threat intelligence, complex incident response |
| **Key decision** | "Are there active threats that our system is not detecting?" |
| **Required skills** | Reverse engineering, malware analysis, YARA/Sigma rule development, SIEM architecture, technical leadership |
| **Approach** | Hypothesis-driven: starts from a hypothesis ("An attacker could use DNS tunneling to exfiltrate data") and searches for evidence in the logs |

**In our lab**: the L3 work is the creation of custom rules in `/var/ossec/etc/rules/local_rules.xml` (rules 100011-100014 for Cowrie), tuning severity levels, and analyzing attack patterns in the honeypot logs to identify coordinated campaigns.
