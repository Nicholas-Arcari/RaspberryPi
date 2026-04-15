>  [Italiano](clamav-yara.md) |  **English**

# ClamAV + YARA: Integrated Antivirus and Malware Analysis

## ClamAV: Periodic Antivirus Scanning

**ClamAV** is the most widely used open-source antivirus on Linux. Integrated with Wazuh, it generates alerts when malware is detected.

```bash
# Installation
sudo apt install clamav clamav-daemon -y

# Update signatures (first run: may take several minutes)
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl start clamav-freshclam

# Test: download the EICAR test file (not an actual virus)
wget -O /tmp/eicar.com "https://secure.eicar.org/eicar.com"

# Manual scan
clamscan /tmp/eicar.com
# /tmp/eicar.com: Win.Test.EICAR_HDB-1 FOUND
```

---

## ClamAV Integration with Wazuh

Automatic scanning of files downloaded by the honeypot.

Add to `ossec.conf` on the agent:

```xml
<!-- Run ClamAV when syscheck detects a new file in the Cowrie download directory -->
<command>
  <name>clamscan</name>
  <executable>clamscan.sh</executable>
  <timeout_allowed>yes</timeout_allowed>
</command>

<active-response>
  <command>clamscan</command>
  <location>local</location>
  <rules_id>554</rules_id>  <!-- New file detected by syscheck -->
</active-response>
```

Create the script `/var/ossec/active-response/bin/clamscan.sh`:

```bash
#!/bin/bash
# Scan the file detected by syscheck with ClamAV
# If positive, Wazuh generates an alert from the ClamAV log

LOCAL=$(dirname $0)
ALERT_FILE=$1
FILENAME=$(echo "$ALERT_FILE" | jq -r '.parameters.alert.syscheck.path')

if [[ -f "$FILENAME" ]]; then
    clamscan --no-summary "$FILENAME" >> /var/log/clamav/wazuh-scan.log 2>&1
fi
```

Add the ClamAV log as a Wazuh source:

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/clamav/wazuh-scan.log</location>
</localfile>
```

Wazuh has built-in rules for ClamAV (rule group `clam`). When ClamAV finds malware, the alert appears on the Dashboard with the malware name and file path.

---

## YARA: Advanced Honeypot File Analysis

**YARA** is the standard tool for malware classification. Unlike ClamAV (signature-based), YARA uses flexible rules based on patterns, strings, and logical conditions.

```bash
# Installation
sudo apt install yara -y
```

### YARA Rules for Our Honeypot

```bash
sudo mkdir -p /var/ossec/ruleset/yara/rules
```

Create `/var/ossec/ruleset/yara/rules/honeypot_malware.yar`:

```yara
rule CoinMiner_Generic {
    meta:
        description = "Detects cryptocurrency mining scripts"
        author = "Homelab SOC"
        severity = "high"
    strings:
        $s1 = "stratum+tcp://" ascii    // Mining pool URL
        $s2 = "xmrig" ascii nocase      // XMRig miner
        $s3 = "minerd" ascii            // CPU miner
        $s4 = "--donate-level" ascii    // XMRig flag
        $s5 = "cryptonight" ascii       // Monero mining algorithm
    condition:
        any of them
}

rule Reverse_Shell {
    meta:
        description = "Detects reverse shell attempts"
        severity = "critical"
    strings:
        $s1 = "/dev/tcp/" ascii                    // Bash reverse shell
        $s2 = "bash -i >& /dev/tcp" ascii          // Classic bash reverse shell
        $s3 = "python -c 'import socket" ascii     // Python reverse shell
        $s4 = "nc -e /bin/" ascii                   // Netcat reverse shell
        $s5 = "exec 5<>/dev/tcp/" ascii            // File descriptor reverse shell
    condition:
        any of them
}

rule SSH_Key_Theft {
    meta:
        description = "Script that attempts to steal SSH keys"
        severity = "critical"
    strings:
        $s1 = ".ssh/id_rsa" ascii
        $s2 = ".ssh/authorized_keys" ascii
        $s3 = "cat /etc/shadow" ascii
        $s4 = "/root/.ssh" ascii
    condition:
        2 of them
}
```

### Automated Scanning

```bash
# Scan all files downloaded by the honeypot with YARA
yara -r /var/ossec/ruleset/yara/rules/ /home/pi/cowrie/downloads/

# Example output:
# CoinMiner_Generic /home/pi/cowrie/downloads/a1b2c3d4...
# Reverse_Shell /home/pi/cowrie/downloads/e5f6g7h8...
```

The integration with Wazuh follows the same pattern as ClamAV: an Active Response script that runs YARA when a new file appears in the downloads directory, and the result is ingested as a log.

> **The combined value:** ClamAV detects known malware (exact signature match). YARA detects behavioral patterns (even in never-before-seen malware). Using them together provides coverage for both known and unknown threats.

---

## Summary: Complete Detection Stack

```
NETWORK LAYER            HOST LAYER               FILE LAYER
-------------            --------------           --------------
Suricata                 Wazuh Agent              ClamAV
|-- IDS signatures       |-- Log analysis         |-- AV signatures
|-- Protocol anomaly     |-- FIM (syscheck)       +-- Updated database
|-- DNS logging          |-- Rootcheck
|-- TLS inspection       |-- Vulnerability det.   YARA
+-- File extraction      |-- CIS Benchmark        |-- Pattern matching
                         +-- Active Response      +-- Custom rules
        |                     |                       |
        +---------------------+-----------------------+
                              v
                     Wazuh Manager (correlation)
                              |
                              v
                     Dashboard (visualization + threat hunting)
```

Each layer covers a different attack surface. Wazuh alone is blind to the network and limited on files. With Suricata, ClamAV, and YARA, the coverage becomes comprehensive.
