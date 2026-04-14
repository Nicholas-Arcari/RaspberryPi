>  [Italiano](README.md) |  **English**

# Honeypot - Cowrie SSH/Telnet with Wazuh SIEM Integration

A cybersecurity project to turn a Raspberry Pi into a "trap" (Honeypot) capable of luring attackers, recording their actions, and analyzing them in real time through a SIEM. Includes the full configuration, custom Wazuh rules, and all the issues I encountered along with their solutions.

## Architecture

```
Attacker (Internet/LAN)
    |
    | SSH port 2222
    v
[Cowrie Container] --JSON log--> [Wazuh Agent] --events--> [Wazuh Manager]
                                                                |
                                                                v
                                                         [Wazuh Indexer]
                                                                |
                                                                v
                                                         [Wazuh Dashboard]
                                                         (Alert + Threat Hunting)
```

## Table of Contents

| # | Section | Description |
|---|---------|-------------|
| 1 | [Theory: What Is a Honeypot](docs/teoria-honeypot.en.md) | Honeypot classification, Cowrie description, MITRE ATT&CK mapping |
| 2 | [Cowrie + Wazuh Installation](docs/installazione-cowrie.en.md) | Architecture, prerequisites, Docker setup, ossec.conf configuration, permission fixes |
| 3 | [Custom Wazuh Rules](docs/regole-wazuh.en.md) | local_rules.xml, rule explanation, real-world Cowrie JSON log example |
| 4 | [Pipeline: From Log to Alert](docs/log-pipeline.en.md) | Full walk-through Phases 1-6, validation with wazuh-logtest |
| 5 | [Alternatives to Cowrie](docs/alternative.en.md) | Honeypot comparison table, OpenCanary and Dionaea installation, robots.txt honeypot, Q&A for analysts |
| 6 | [Troubleshooting + Final Test](docs/troubleshooting.en.md) | 4 errors resolved with hands-on experience, end-to-end system test |

## Final Test (Summary)

To verify end-to-end operation:

1. **Brute force** - `ssh -p 2222 root@<IP_RASPBERRY>` with random passwords --> alert rule 100011
2. **Intrusion** - Weak password (`root`, `12345`) --> alert rule 100012 (level 10, critical)
3. **Post-exploitation** - Commands like `whoami`, `cat /etc/shadow`, `wget` --> alert rule 100013
4. **Dashboard** - Filter by `rule.id: 100012` or `rule.mitre.id: T1078` in Threat Hunting

Full details in the [Troubleshooting + Final Test](docs/troubleshooting.en.md) section.

---

Next step: [SOC Analyst / Wazuh](../SOC%20Analyst/) - SIEM Wazuh installation and configuration.
