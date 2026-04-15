>  [Italiano](threat-model.md) |  **English**

# Threat Model: STRIDE Analysis of the Lab

A formalized threat model identifies **what to protect**, **from whom**, and **how it can be attacked** - before it happens. I use the **STRIDE** framework (Microsoft), which classifies threats into 6 categories.

---

## Assets to Protect

| Asset | Value | Impact if compromised |
|---|---|---|
| **NAS data** (photos, documents, backups) | High | Personal data loss, privacy violation |
| **SSH credentials / private keys** | Critical | Full access to the host and all services |
| **Wazuh alert database** (OpenSearch) | Medium | The attacker deletes evidence of their intrusion |
| **Network configuration** (UFW, iptables) | High | The attacker opens ports or disables the firewall |
| **Docker containers** | Medium | Lateral movement if the container is used as a pivot |
| **Home network** (other devices) | High | The attacker reaches PCs, phones, smart TVs |

---

## Attack Surface

```
                        INTERNET
                           |
           +---------------+---------------+
           v               v               v
      :2222/TCP       :51820/UDP      Ngrok tunnel
      (Honeypot)      (WireGuard)     (fallback)
      EXPOSED         EXPOSED         EXPOSED
           |               |               |
           +-------+-------+               |
                   v                       |
              Raspberry Pi                 |
           +-------------------------------+
           |
    +------+------------------------------+
    |      v                              |
    |  :22 (SSH)     LAN ONLY             |
    |  :80 (OMV)     LAN ONLY             |
    |  :443 (Wazuh)  LAN ONLY             |
    |  :9200 (Index) LAN ONLY             |
    |  :9443 (Port.) LAN ONLY             |
    +-----------    ----------------------+
```

Ports exposed to the Internet: **only 2** (Honeypot and WireGuard). Everything else is accessible only from the LAN.

---

## Probable Threat Actors

| Type | Motivation | Capability | Likelihood |
|---|---|---|---|
| **Automated bots** (Mirai, SSH scanners) | Add the Pi to a botnet | Low (common credentials, known exploits) | **Very high** (24/7, thousands per day) |
| **Script kiddie** | Curiosity, vandalism | Low-Medium (preconfigured tools) | Medium |
| **Targeted attacker** | Access to NAS data | Medium-High (custom exploits, persistence) | Low (home lab, not a high-value target) |
| **Insider** (anyone on the LAN) | Unauthorized access | High (already inside the network) | Low (home environment) |

---

## STRIDE Analysis by Component

**STRIDE** classifies threats into:
- **S**poofing (impersonating an identity)
- **T**ampering (modifying data or code)
- **R**epudiation (denying having performed an action)
- **I**nformation Disclosure (exposing confidential information)
- **D**enial of Service (making the service unavailable)
- **E**levation of Privilege (gaining unauthorized permissions)

### Cowrie Honeypot (Internet-facing)

| Threat | Category | Concrete scenario | Mitigation |
|---|---|---|---|
| Container escape | **E** | The attacker exploits a runc CVE (e.g., CVE-2019-5736) to escape the container and gain root on the host | Docker kept up to date, unprivileged container, no Docker socket mounted, seccomp + AppArmor enabled |
| LAN pivot | **E** | After a container escape, the attacker scans the local network | UFW: deny outbound to 192.168.0.0/24 (except gateway), VLAN segmentation |
| DoS via flood | **D** | Thousands of simultaneous connections exhaust container resources | Cgroup memory/pids limits, rate limiting on UFW |
| Fingerprinting | **I** | The attacker identifies Cowrie from the SSH banner (OpenSSH version too old) and avoids it | Configure `ssh_version_string` in `cowrie.cfg` with a plausible version |

### WireGuard VPN (Internet-facing)

| Threat | Category | Concrete scenario | Mitigation |
|---|---|---|---|
| Compromised private key | **S** | If someone steals a client's private key, they can impersonate that VPN client | Keys stored only on the device, immediate revocation from the wg-easy Web UI |
| Key brute force | **S** | Attempting to guess the Curve25519 key | Impossible: 2^128 combinations, no negotiation (the server silently ignores packets with the wrong key) |
| Web UI credential stuffing | **E** | Brute force on port 51821 (management Web UI) | Web UI accessible only from LAN (UFW), strong password |
| Replay attack | **T** | Capturing and replaying VPN packets | WireGuard uses a monotonically increasing nonce counter: replays are discarded |

### Wazuh SIEM (LAN only)

| Threat | Category | Concrete scenario | Mitigation |
|---|---|---|---|
| Alert tampering | **T** | The attacker modifies or deletes alerts to conceal their activity | Dashboard access restricted to LAN, strong credentials, FIM on `/var/ossec/logs/` |
| API abuse | **E** | Unauthorized access to the Wazuh API (port 55000) to register fake agents | UFW: port 55000 LAN only, API authentication with token |
| Information disclosure | **I** | Alerts contain honeypot passwords, internal IPs, configurations - if readable from the outside | Port 9200 (OpenSearch) not exposed to the Internet, TLS for all communications |
| Log injection | **T** | A compromised agent sends fake logs to the Manager to generate false positives | mTLS: only agents with a certificate signed by the same CA can communicate |

### NAS / OpenMediaVault (LAN only)

| Threat | Category | Concrete scenario | Mitigation |
|---|---|---|---|
| Data exfiltration | **I** | After a container escape, the attacker mounts SMB shares and steals data | Container without access to NAS volumes, SMB with authentication, restrictive ACLs |
| Ransomware | **T** | Malware encrypts files on network shares | Periodic offline backups (not accessible via network), read-only permissions where possible |
| Default credentials | **S** | The default OMV credentials (`admin/openmediavault`) were not changed | Change on first access (documented in the NAS section) |

---

## Accepted Residual Risks

No system is 100% secure. These are the risks I have consciously accepted:

| Residual risk | Why I accept it | Partial mitigation |
|---|---|---|
| Kernel exploit = container escape | Impossible to eliminate without a VM (excessive overhead for RPi) | Kernel kept up to date, seccomp, AppArmor |
| Ngrok tunnel = third party | Honeypot traffic passes through Ngrok servers | No sensitive data in transit (only honeypot sessions) |
| Self-signed certificates | Not validated by an external CA | Acceptable in a home environment, all components on the same host |
| Single point of failure | One Pi for all services | Periodic backups, MicroSD as recovery boot |
