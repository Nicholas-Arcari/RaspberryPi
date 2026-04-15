>  [Italiano](reconnaissance.md) |  **English**

# Phase 1: Reconnaissance - Discovering Open Ports

## Nmap Scan

I launched a full scan from another computer (Kali Linux) towards the Raspberry Pi:

```bash
nmap -sS -p- -T4 -v <IP_RASPBERRY>
```

**Flag explanation:**

| Flag | Meaning | Technical detail |
|---|---|---|
| `-sS` | SYN scan (half-open) | Sends a SYN packet, waits for SYN-ACK but does not complete the TCP handshake (does not send ACK). Faster and stealthier than a connect scan (`-sT`) because it does not establish full connections |
| `-p-` | Scan all 65535 ports | By default Nmap only scans the 1000 most common ports. `-p-` scans all of them |
| `-T4` | Timing template "aggressive" | Reduces timeouts and increases parallelism. Values range from T0 (paranoid) to T5 (insane). T4 is a good speed/reliability trade-off |
| `-v` | Verbose | Shows ports as they are found, without waiting for the scan to finish |

---

## The Alarming Result

Not only was port 2222 (Honeypot) open, but a "Christmas tree" of services:

| Port | Service | Risk |
|---|---|---|
| **22** | Real SSH | **CRITICAL** - An attacker could attempt brute force against the actual operating system |
| **443** | Wazuh Dashboard | **HIGH** - The SIEM login page was visible from the outside |
| **2222** | Cowrie Honeypot | Expected - this is the service we want to expose |
| **9200** | Wazuh Indexer (OpenSearch) | **CRITICAL** - REST API of the alert database, potentially exploitable to extract information |
| **55000** | Wazuh API | **HIGH** - Manager management API |

---

## Full Scan Output

This is the real (anonymized) output from the SYN scan launched from the Kali machine:

```
Starting Nmap 7.94SVN ( https://nmap.org ) at 2025-XX-XX 14:32 CET
Initiating ARP Ping Scan at 14:32
Scanning 192.168.0.XXX [1 port]
Completed ARP Ping Scan at 14:32, 0.04s elapsed (1 total hosts)
Initiating SYN Stealth Scan at 14:32
Scanning 192.168.0.XXX [65535 ports]
Discovered open port 443/tcp on 192.168.0.XXX
Discovered open port 22/tcp on 192.168.0.XXX
Discovered open port 9200/tcp on 192.168.0.XXX
Discovered open port 2222/tcp on 192.168.0.XXX
Discovered open port 55000/tcp on 192.168.0.XXX
Discovered open port 1514/tcp on 192.168.0.XXX
Discovered open port 1515/tcp on 192.168.0.XXX
Completed SYN Stealth Scan at 14:33, 26.37s elapsed (65535 total ports)
Nmap scan report for 192.168.0.XXX
Host is up (0.00045s latency).
Not shown: 65528 closed tcp ports (reset)
PORT      STATE SERVICE
22/tcp    open  ssh
443/tcp   open  https
1514/tcp  open  fujitsu-dtc
1515/tcp  open  ifor-protocol
2222/tcp  open  EtherNetIP-1
9200/tcp  open  wap-wsp
55000/tcp open  unknown
MAC Address: XX:XX:XX:XX:XX:XX (Raspberry Pi Ltd)

Nmap done: 1 host scanned in 26.41 seconds
           Raw packets sent: 65536 (2.884MB) -- Rcvd: 65536 (2.621MB)
```

**Line-by-line analysis:**

- **ARP Ping Scan**: Nmap first verifies that the host is alive with an ARP request (Layer 2). On the same LAN, ARP is more reliable than ICMP because it cannot be blocked by the firewall
- **65535 ports**: the full scan took ~26 seconds. On ARM64 with a local connection, T4 is fast enough
- **`closed tcp ports (reset)`**: closed ports respond with RST (Reset). If they had been `filtered`, they would not have responded at all - indicating a firewall performing silent drops
- **`fujitsu-dtc` / `ifor-protocol` / `EtherNetIP-1`**: Nmap assigns service names based on the file `/usr/share/nmap/nmap-services` (port -> historical name mapping). These names are **misleading** - port 1514 is not actually Fujitsu, it is the Wazuh event channel. Port 2222 is not EtherNet/IP, it is Cowrie. To identify the real services, a version detection scan (`-sV`) is needed
- **MAC Address: Raspberry Pi Ltd**: the vendor OUI from the MAC address immediately identifies the device as a Raspberry Pi. An attacker on the same LAN knows exactly what they are attacking

---

## Version Detection Scan

To confirm the real services behind each port:

```bash
nmap -sV -p 22,443,1514,1515,2222,9200,55000 192.168.0.XXX
```

```
PORT      STATE SERVICE     VERSION
22/tcp    open  ssh         OpenSSH 8.4p1 Debian 5+deb11u3 (protocol 2.0)
443/tcp   open  ssl/https   nginx 1.25.3
1514/tcp  open  tcpwrapped
1515/tcp  open  tcpwrapped
2222/tcp  open  ssh         OpenSSH 6.0p1 Debian 4+deb7u2 (protocol 2.0)
9200/tcp  open  http        OpenSearch REST API 2.13.0
55000/tcp open  ssl/unknown
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel
```

**Critical observations from an analyst's perspective:**

1. **Port 22 vs 2222**: the OpenSSH version on port 22 is `8.4p1` (the real system version), while on 2222 it is `6.0p1` (a deliberately outdated version emulated by Cowrie). A skilled attacker would notice the discrepancy and realize that 2222 is a honeypot. Cowrie can be configured to emulate more recent versions in the `cowrie.cfg` file (`ssh_version_string`)
2. **OpenSearch 9200**: the REST API is reachable. A `curl https://192.168.0.XXX:9200/_cat/indices` would return the list of indices (including `wazuh-alerts-*`). Without client TLS authentication, anyone could read the alerts
3. **`tcpwrapped`**: Nmap cannot identify the service because the connection is closed after the TCP handshake. The Wazuh Manager only accepts connections from agents registered with a valid certificate
4. **nginx 1.25.3**: reveals the exact version of the Dashboard reverse proxy. An attacker would search for known CVEs for that specific version

---

## The Root Cause: DMZ on the Router

I had initially placed the Raspberry Pi in the router's **DMZ** for convenience during setup. DMZ (on a consumer router) means "forward ALL traffic to this IP" - it completely bypasses the router's firewall and exposes every Raspberry Pi service directly to the Internet.

> **Critical lesson:** DMZ on a consumer router is not the same thing as a "demilitarized zone" in an enterprise architecture. In enterprise environments, a DMZ is a separate network with dedicated firewalls and granular rules. On a home router, "DMZ" = "expose everything" - it is the equivalent of removing the firewall.

**MITRE ATT&CK mapping:**
- **T1046 - Network Service Discovery**: Nmap detects exposed services
- **T1190 - Exploit Public-Facing Application**: If an exposed service has a known CVE, it can be exploited
