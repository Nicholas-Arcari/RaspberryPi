>  [Italiano](risorse-e-credenziali.md) |  **English**

# Runbook 09 - Resource exhaustion and lost credentials

> **When to use this runbook:** the system is slow or unstable because the disk is full, RAM is exhausted (OOM) or the CPU is thermally throttling; or you lost the password of one of the services (OMV, Portainer, Pi-hole, WireGuard, Wazuh) and need to reset it. Two frequent problems grouped together because they are the "small emergencies" that, ignored, become big faults (a full disk takes down Docker and Wazuh, see [Runbook 03](wazuh-dashboard-recovery.en.md)).

---

## Part A - Full disk

A full root is the most underestimated root cause: it pushes the Wazuh indexer into read-only, prevents Docker from starting, blocks the logs and simulates a thousand different faults.

### A.1 Diagnosis: how much and who

```bash
# How much space is left on root?
df -h /
# Usage > 90% <-- danger zone. > 95% <-- OpenSearch goes read-only

# Who is taking the space? The usual suspects on this lab:
sudo du -xh --max-depth=2 /var 2>/dev/null | sort -rh | head -15
# Typical candidates:
#   /var/log/journal      -> systemd logs with no ceiling
#   /var/lib/docker       -> images and container logs
#   /var/ossec/logs       -> Wazuh logs/alerts
#   /var/lib/wazuh-indexer -> OpenSearch indices growing forever
```

### A.2 Cleanup, from safest to most aggressive

```bash
# 1. systemd logs: put a ceiling (safe)
sudo journalctl --vacuum-size=200M
# permanent: in /etc/systemd/journald.conf -> SystemMaxUse=200M

# 2. Unused Docker logs and images (careful: -a removes unused images)
docker system df                       # shows where the Docker space is
docker image prune -a                  # removes dangling/unused images
docker builder prune                   # build cache
# limit container logs in the future: in /etc/docker/daemon.json ->
#   "log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}

# 3. Old application logs (Cowrie can generate a lot under attack)
sudo find /var/log -type f -name "*.gz" -mtime +14 -delete
docker exec cowrie sh -c 'find /home/cowrie/cowrie-git/var/log -name "*.json" -mtime +14'

# 4. Old Wazuh indices: the structural cure is an ISM retention policy.
#    Delete obsolete indices (adapt the pattern and the date):
curl -sk -u admin:admin "https://localhost:9200/_cat/indices/wazuh-alerts-*?v&s=index"
curl -sk -u admin:admin -X DELETE "https://localhost:9200/wazuh-alerts-4.x-2025.01.*"
```

### A.3 Unblock what got blocked by the full disk

```bash
# OpenSearch stays read-only even after freeing space: it must be unblocked
curl -sk -u admin:admin -X PUT "https://localhost:9200/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'

# Docker didn't start because of the full disk: after the cleanup
sudo systemctl start docker
```

---

## Part B - RAM exhausted (OOM)

On the Pi 5 (8GB), the Wazuh Indexer + Dashboard + the containers compete for memory. When it runs out, the kernel invokes the **OOM killer** which kills a process of its choosing (often the Java indexer, the biggest one).

```bash
# Who was killed by the OOM killer?
sudo dmesg -T | grep -i "killed process"
# "Out of memory: Killed process 1234 (java)" -> it was the indexer

# Current RAM and swap status
free -h
# swap at 0 and RAM almost full <-- no cushion: the next spike kills something
```

Remedies:

```bash
# 1. Cap the indexer heap (the #1 devourer). In /etc/wazuh-indexer/jvm.options:
#    -Xms1g / -Xmx1g  (no more than 1-2g on a shared Pi)
sudo systemctl restart wazuh-indexer

# 2. Put a RAM ceiling on the non-critical containers (so they don't kill the indexer)
#    in the compose:  mem_limit: 256m   (e.g. cowrie, pihole)

# 3. Add swap as a cushion (not as a structural solution)
sudo dphys-swapfile swapoff
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
sudo dphys-swapfile setup && sudo dphys-swapfile swapon
```

---

## Part C - Thermal throttling

The Pi 5 under load (or with poor heat dissipation) exceeds ~80-85 C and reduces the frequency to protect itself: the system becomes very slow for no apparent reason.

```bash
# Temperature and throttling status
vcgencmd measure_temp
vcgencmd get_throttled
# 0x0 = all ok
# bit 0x1 = under-voltage NOW; 0x4 = throttling NOW; 0x8 = freq cap active
# 0x50000/0x50005 = it already happened (under-voltage/throttling in the past)
```

| Value | Meaning | Remedy |
|---|---|---|
| Temp > 80 C | Insufficient dissipation | Active heatsink/fan, better ventilation, open case |
| `throttled` with under-voltage bit | Inadequate power supply | Official 27W power supply (the NVMe increases consumption) |

> Under-voltage and thermal throttling are often mistaken for software problems (random panics, slowness, reboots). On this lab, with the NVMe connected, the right power supply and adequate cooling prevent an entire class of seemingly mysterious faults. See also [Runbook 01, Part C](accesso-perso-e-boot.en.md).

---

## Part D - Lost credentials: reset per service

You lost access to a service. Here is the reset for each. (SSH is in [Runbook 01](accesso-perso-e-boot.en.md); Wazuh in [Runbook 03](wazuh-dashboard-recovery.en.md).)

### OpenMediaVault (admin web UI)

```bash
# From the shell (SSH/console), reset the OMV admin password
sudo omv-firstaid
# Interactive menu -> "Change the web control panel password"
# Alternatively, direct read:
sudo omv-confdbadm read conf.webadmin       # verify the user
```

### Portainer (admin web UI)

Portainer allows the reset only with access to the host shell, via an official container that regenerates the admin:

```bash
docker stop portainer
docker run --rm -v portainer_data:/data portainer/helper-reset-password
# Prints a new temporary password for the admin user
docker start portainer
```

### Pi-hole (dashboard)

```bash
# Set a new dashboard password
docker exec -it pihole pihole -a -p
# Type the new password (or leave empty to remove it, not recommended)
```

### WireGuard (wg-easy web UI)

The wg-easy UI password is a hash in the compose environment variable. Reset:

```bash
# Generate the new hash (bcrypt) and replace it in PASSWORD_HASH in the compose/.env
docker run --rm ghcr.io/wg-easy/wg-easy wgpw 'NewPassword'
# Copy the resulting hash into docker-compose.yml (or .env), then:
docker compose up -d --force-recreate wireguard
```

> **The lesson:** each of these resets requires access to the host shell. It is a reminder that **host access is the master key**: protect it (Runbook 01) and put its recovery credentials in the offline password manager. And after every reset, **update the password manager**: the next "I lost the password" must be the last.

---

## Prevention

- **Disk:** cap the logs (journald + Docker), an ISM retention policy on Wazuh, and a Wazuh alert when `/` exceeds 80%. A full disk is 100% preventable.
- **RAM:** capped indexer heap, `mem_limit` on the containers, swap as a cushion. Have RAM monitored.
- **Thermal:** adequate cooling + official power supply. Check `get_throttled` in the periodic checklist.
- **Credentials:** all in the password manager, including the recovery ones. A credential that lives only in your head is an incident waiting to happen.

---

## Links

- Full disk that caused the Wazuh crash -> [Runbook 03: Wazuh dashboard](wazuh-dashboard-recovery.en.md)
- Container killed by OOM (exit 137) -> [Runbook 04: VPN and containers](vpn-e-container-recovery.en.md)
- Under-voltage / thermal panics -> [Runbook 01: lost access and boot](accesso-perso-e-boot.en.md)
- Saving the credentials in the backup -> [Runbook 08: backup and disaster recovery](backup-e-disaster-recovery.en.md)
