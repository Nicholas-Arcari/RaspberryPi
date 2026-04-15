>  [Italiano](suricata.md) |  **English**

# Suricata IDS/IPS: The Missing Component in Wazuh

Wazuh excels at log analysis (host-based detection), but it is blind to **network traffic**. It cannot see malformed packets, network exploits, C2 (Command & Control) communications, or DNS tunneling - it only sees what application logs report.

**Suricata** is an open-source Network IDS/IPS that analyzes traffic in real time using signature-based rules. The Wazuh + Suricata combination is the de facto standard for a complete SOC:

```
Network traffic --> [Suricata] --> eve.json --> [Wazuh Agent] --> [Manager] --> Dashboard
                      |                           (log_format: json)
                      | Analyzes:
                      |-- Signature matching (ET Open rules)
                      |-- Protocol anomaly detection
                      |-- TLS/SSL inspection
                      |-- DNS query logging
                      |-- HTTP request logging
                      +-- File extraction (MD5/SHA256)
```

---

## What Suricata Detects That Wazuh Alone Cannot See

| Threat | Wazuh (without Suricata) | Wazuh + Suricata |
|---|---|---|
| Nmap SYN scan | Only sees UFW logs (post-firewall) | Detects the scan from the packet pattern (SID:2100001) |
| Network exploit (EternalBlue, Log4Shell) | Not detected (no application log) | Detects the signature in the exploit payload |
| C2 communication (beacon, reverse shell) | Not detected (traffic exits on legitimate ports) | Detects known C2 patterns (Cobalt Strike, Metasploit) |
| DNS tunneling (data exfiltration) | Not detected (Pi-hole sees the query, not the payload) | Detects anomalous DNS queries (length, entropy, frequency) |
| Malware download (HTTP) | Not detected (Cowrie captures files, but what about real traffic?) | Detects the file hash/signature in the traffic |
| SSH brute force | **Yes** (from auth.log) | **Yes** (also from traffic, as a backup) |

---

## Installation on Raspberry Pi

```bash
# Suricata is in the Debian repositories
sudo apt install suricata suricata-oinkmaster -y

# Verify version
suricata --build-info | head -5
```

---

## Basic Configuration (`/etc/suricata/suricata.yaml`)

```yaml
# Interface to monitor (same as the Pi's)
af-packet:
  - interface: end0
    cluster-id: 99
    cluster-type: cluster_flow    # Flow-based balancing (not per-packet)
    defrag: yes

# Network to protect (HOME_NET)
vars:
  address-groups:
    HOME_NET: "[192.168.0.0/24, 192.168.150.0/24, 10.8.0.0/24]"
    EXTERNAL_NET: "!$HOME_NET"

# Output in JSON format (Wazuh-compatible)
outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /var/log/suricata/eve.json
      types:
        - alert                    # Alert when a rule matches
        - dns                      # All DNS queries (useful for threat hunting)
        - http                     # All HTTP requests (URL, user-agent, referer)
        - tls                      # TLS handshakes (SNI, certificate, JA3 fingerprint)
        - files                    # Files extracted from traffic (with hashes)
```

---

## Rules: Emerging Threats Open (ET Open)

```bash
# Update the ET Open rules (free, updated daily)
sudo suricata-update

# Rules are downloaded to /var/lib/suricata/rules/suricata.rules
# They contain ~40,000+ signatures for:
# - Known malware (trojans, ransomware, coinminers)
# - Exploits (specific CVEs)
# - C2 communication (Cobalt Strike, Metasploit, etc.)
# - Policy violations (torrents, unauthorized VPNs)
# - Scans and reconnaissance

# Start Suricata
sudo systemctl enable --now suricata
```

---

## Integration with Wazuh

On the **Manager**, add Suricata as a log source in `/var/ossec/etc/ossec.conf`:

```xml
<!-- Suricata log (JSON format like Cowrie) -->
<localfile>
  <log_format>json</log_format>
  <location>/var/log/suricata/eve.json</location>
</localfile>
```

Wazuh already has **built-in rules for Suricata** (rule group `suricata`). After restarting the Manager, Suricata alerts will automatically appear on the Dashboard with MITRE ATT&CK mapping.

Example of a correlated alert on the Dashboard:

```
[Suricata] ET MALWARE Win32/Emotet CnC Activity (rule 2025636, severity 1)
    src_ip: 192.168.0.50  dst_ip: 185.X.X.X  dst_port: 443
    + [Wazuh FIM] File modified: /usr/bin/curl (hash changed)
    + [Wazuh] Anomalous outbound connection from 192.168.0.50
    = Possible compromise of the Windows PC with Emotet
```

> **Note on resources:** Suricata on Raspberry Pi 5 works, but with limitations. On a saturated gigabit LAN, Suricata may drop packets. For our use case (home traffic, ~10-50 Mbps), it is more than sufficient. Monitor with `suricata -c /etc/suricata/suricata.yaml --dump-config | grep "detect.profile"` and `sudo suricatasc -c "dump-counters"`.
