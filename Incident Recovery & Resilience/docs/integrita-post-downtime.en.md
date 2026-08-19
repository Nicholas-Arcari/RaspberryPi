>  [Italiano](integrita-post-downtime.md) |  **English**

# Runbook 06 - Post-downtime integrity

> **When to use this runbook:** the system was off, unreachable or out of your control for a period (a holiday, a blackout, a fault) and you want to verify, before trusting it again, that **nobody got in, nothing was tampered with and there is no man-in-the-middle** on the network. It is the incident-response runbook applied to "I don't know what happened while I wasn't watching".

Guiding principle: **assume breach, then disprove it with evidence.** You do not start from "it's probably all fine"; you start from "what proves to me that it's all fine?". If you do not have a baseline (Golden Rule no.2 of the [README](../README.en.md)), many of these checks lose their strength: this is why the baseline is captured from a healthy system.

> **Order matters:** if at ANY point you find a strong indicator of compromise, **stop and isolate** before continuing to "fix" things (disconnect the network, do not power off - RAM is evidence). See the Containment section at the bottom.

---

## Phase 1 - Who got in, and when

```bash
# Last successful logins (users, IPs, times). Look for sessions during the downtime period.
last -aiF | head -30
# Rows with unknown IPs or times when the system was supposed to be off <-- SUSPICIOUS

# Last FAILED logins (brute force)
sudo lastb -aiF | head -30

# Accepted SSH logins in the period (who, from where, with which method)
sudo journalctl -u ssh --since "2026-08-01" --until "2026-08-17" | grep -i "Accepted"
# Expected: only your logins, from your IPs, "Accepted publickey"
# "Accepted password" <-- alarm: password auth should be disabled

# Active sessions right now (is there anyone besides you?)
who -a
w
```

## Phase 2 - Users, keys and privileges: did they change?

An attacker who gets in creates persistence: a new user, a new SSH key, a sudo entry.

```bash
# New users with a login shell or UID 0 (classic backdoor)
awk -F: '($3>=1000 || $3==0) && $7 !~ /nologin|false/ {print $1, $3, $7}' /etc/passwd
# Expected: only your users. A second UID 0 = serious backdoor

# Authorized SSH keys: any you did not put there?
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys \
         /var/lib/openmediavault/ssh/authorized_keys/*; do
  [ -f "$f" ] && echo "== $f ==" && cat "$f"
done
# Compare EVERY key with your notes. An unknown key = someone else's persistent access

# Recent changes to sensitive auth files (mtime in the downtime period)
sudo ls -la --time-style=full-iso /etc/passwd /etc/shadow /etc/sudoers
sudo find /etc/sudoers.d -type f -newermt "2026-08-01" -ls
```

## Phase 3 - Persistence: cron, services, startup

```bash
# Cron of all users + recently modified system cron
for u in $(cut -f1 -d: /etc/passwd); do crontab -l -u "$u" 2>/dev/null | sed "s/^/[$u] /"; done
sudo find /etc/cron* /var/spool/cron -type f -newermt "2026-08-01" -ls

# systemd services created/modified recently (modern persistence)
sudo find /etc/systemd/system /lib/systemd/system -name "*.service" -newermt "2026-08-01" -ls
systemctl list-unit-files --state=enabled    # compare with the baseline

# Look for suspicious startup enablements
grep -R "" /etc/rc.local 2>/dev/null
```

## Phase 4 - File integrity: FIM and packages

Here the baseline pays off. Wazuh FIM recorded every change to the monitored files: query it for the period.

```bash
# Changes detected by FIM in the period (from the Wazuh dashboard: Integrity Monitoring module)
# From the CLI, the recorded syscheck alerts:
sudo grep -i syscheck /var/ossec/logs/alerts/alerts.json | \
  grep -E "2026-08-(0[1-9]|1[0-7])" | tail -50
# Every change to /etc, to binaries, to configs must be justified by an action of YOURS

# Integrity of the installed packages (are the system binaries the original ones?)
sudo apt install -y debsums >/dev/null 2>&1
sudo debsums -c 2>/dev/null
# Expected: no output. Every listed file = a binary modified from the package <-- serious

# Known rootkits/backdoors
sudo apt install -y rkhunter chkrootkit >/dev/null 2>&1
sudo rkhunter --check --sk --report-warnings-only
sudo chkrootkit -q
```

## Phase 5 - Network surface: what is listening now?

```bash
# Listening ports and their process: compare with the baseline (Runbook 08)
sudo ss -tulnp
# A new port/service you did not set up = a possible implant (reverse shell, C2)

# Established outbound connections (an implant "phones home")
sudo ss -tunp state established
# Unknown, repeated destination IPs, towards odd ports <-- investigate (beaconing)
```

---

## Phase 6 - Man-in-the-middle on the LAN

This is the part specific to the question "did someone set themselves up as a man-in-the-middle?". A MITM on a LAN is almost always done with **ARP spoofing** (the attacker convinces the devices that their MAC is the gateway's) or with a **rogue DHCP/DNS** (handing out themselves as the gateway or resolver).

### 6.1 Verify the gateway MAC (anti ARP-spoofing)

```bash
# Who claims to be the gateway 192.168.0.1, and with which MAC?
ip neigh show 192.168.0.1
# Compare the MAC with the REAL one of the router (read once, from healthy, and noted in the baseline).
# A MAC different from expected = someone is impersonating the gateway <-- MITM

# The whole ARP table: two IPs with the same MAC, or the gateway MAC on multiple IPs?
ip neigh show
arp -an
# Classic ARP spoofing anomalies:
#  - the gateway MAC also appears on another IP
#  - an IP "flaps" between two different MACs
```

### 6.2 Rogue DHCP: is there a second DHCP server?

```bash
# Probe the DHCP servers present on the LAN (ONLY the router should answer)
sudo apt install -y dhcpdump isc-dhcp-client >/dev/null 2>&1
sudo nmap --script broadcast-dhcp-discover 2>/dev/null | grep -E "Server Identifier|Router|DNS"
# Expected: a single Server Identifier = 192.168.0.1
# Two replies / a different server <-- rogue DHCP: someone wants to become your gateway/DNS
```

### 6.3 DNS: am I using the right resolver?

```bash
# Is the effective DNS the expected Pi-hole?
resolvectl status | grep "DNS Servers" || cat /etc/resolv.conf
# A DNS different from 192.168.0.250 that you did not set <-- DNS hijacking

# Is the effective gateway the right one?
ip route | grep default
# default via an IP different from 192.168.0.1 <-- hijacked route
```

### 6.4 Certificates and known_hosts (MITM on TLS/SSH)

An active MITM on TLS/SSH changes the cryptographic fingerprints: it is the most reliable signal.

```bash
# Is the Pi's SSH host fingerprint still the one you know?
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# Compare with the fingerprint noted in the baseline. Different = host key changed
# (or a reinstall, or MITM). Clients that receive a "host key changed" must NOT ignore it.

# From the clients: a "REMOTE HOST IDENTIFICATION HAS CHANGED" warning towards the Pi
# is exactly the symptom of SSH MITM and must never be bypassed lightly.
```

---

## Containment: what to do if you find something

If any phase shows a strong indicator (unknown user, foreign key, modified binary, spoofed gateway MAC):

1. **Isolate, do not power off.** Disconnect the network cable (or block everything with `ufw default deny`). Do not power off: RAM and live processes are evidence. If you must choose, isolate from the network.
2. **Do not "clean up" immediately.** Deleting the backdoor destroys the evidence needed to understand how it got in. First document (screenshots, copy of the logs, `ss`, `ps auxf`, ARP table).
3. **Collect the volatile evidence:** `ps auxf`, `ss -tunp`, `who`, `last`, `ip neigh`, `docker ps`, a copy of `/var/ossec/logs/` and `/var/log/`.
4. **Determine the blast radius:** was the access only to the Pi or also to other hosts? The credentials on it (WireGuard keys, Wazuh password, SMB) must be considered compromised and rotated.
5. **Restore from a trusted state:** in case of a confirmed compromise of the binaries, the clean path is to reinstall from scratch and restore **only the data** (not the binaries) from backup -> [Runbook 08](backup-e-disaster-recovery.en.md). Rotate all credentials and keys.

---

## Prevention (so these checks work)

- **Capture the baseline from healthy** (Golden Rule no.2): real gateway MAC, SSH host fingerprint, list of listening ports, hashes of critical binaries, list of users and keys. Without a baseline, "did it change?" has no answer.
- Keep Wazuh **FIM in realtime** on `/etc`, `/root`, the binaries and the `authorized_keys`: it is the recorder that makes this investigation possible after the fact.
- Enable **static ARP** for the gateway on critical clients, or an **ARP inspection** feature on the managed switch, to make ARP spoofing much harder.
- Have Wazuh **alert in realtime** on: new user, new SSH key, `Accepted password` over SSH, modification of `/etc/sudoers`. That way you do not have to wait for a downtime to notice.

---

## Links

- Proving the defenses (including FIM) work -> [Runbook 05: verifying active defenses](verifica-difese-attive.en.md)
- Full network health check (rogue DHCP, ARP, VLAN) -> [Runbook 07: LAN health check](lan-health-check.en.md)
- Clean restore from backup after compromise -> [Runbook 08: backup and disaster recovery](backup-e-disaster-recovery.en.md)
- Structured incident response (NIST phases) -> [SOC Analyst / incident-response](../../SOC%20Analyst/docs/incident-response.en.md)
