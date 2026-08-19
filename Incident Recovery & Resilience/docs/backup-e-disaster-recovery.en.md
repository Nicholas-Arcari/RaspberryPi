>  [Italiano](backup-e-disaster-recovery.md) |  **English**

# Runbook 08 - Backup and disaster recovery

> **When to use this runbook:** to design what to save and how (before the disaster), and to rebuild the entire lab from scratch if the Pi dies, the NVMe corrupts, or a compromise forces a clean reinstall (after [Runbook 06](integrita-post-downtime.en.md)). It is the safety net all the other runbooks rest on.

Three principles guide every decision:

1. **Separate binaries from data.** The binaries (OS, packages, Docker images) are **recreated** from scripts and registries: you do not need to back up the system, you need to be able to rebuild it. The **data and configurations** are the only irreproducible thing: they are what must be saved.
2. **The 3-2-1 rule.** At least **3** copies of the data, on **2** different media, of which **1** off-site (outside the house/off the Pi). A backup on the same NVMe you are protecting is not a backup.
3. **An untested backup is not a backup** (Golden Rule no.3): the restore procedure must be tried at least once, cold.

---

## Part A - What to save (analysis by RPO)

Not everything has the same value. For each component, the RPO (how much data I can lose) decides what goes into the backup.

| Component | What to save | RPO | Why |
|---|---|---|---|
| **OMV** | System config (`omv-confdbadm read ...` / OMV native backup), `/etc/openmediavault/config.xml` | Low | Recreating shares, users, permissions by hand is long |
| **Docker** | The `docker-compose.yml` files + the `.env` + the mounted **volumes** | Low | The volumes contain the services' data (Pi-hole config, DBs, etc.) |
| **Wazuh** | `/var/ossec/etc/` (ossec.conf, custom rules/decoders), `/etc/wazuh-*`, the certificates, the passwords | Near zero | The custom rules (Cowrie 100010-100013) are pure work |
| **WireGuard** | The server **private keys** and the peer configs (wg-easy volume) | Near zero | Losing the keys = reconfiguring every client |
| **Pi-hole** | "Teleporter" export (blocklist, whitelist, config), or the volume | Medium | The lists re-download, but the customizations do not |
| **Host security** | `/etc/ufw/`, `/etc/fail2ban/jail.local`, `/etc/ssh/sshd_config`, `/etc/sysctl.d/` | Low | Rebuilding the hardening from memory is risky |
| **Host identity** | SSH host keys (`/etc/ssh/ssh_host_*`), `authorized_keys` | Medium | Avoids the "host key changed" warning to clients after the restore |
| **Automation** | `scripts/setup.sh` (already in git) | - | It is the recipe to recreate the binaries |
| **Baseline** | Binary hashes, gateway MAC, SSH fingerprint, port/user list | Low | Needed by Runbooks 05 and 06; must be saved from healthy |

Note: you do **NOT** need to back up `/var/lib/docker` (the images) or the operating system: they are recreated with `docker compose pull` and `setup.sh`.

---

## Part B - How to save

### B.1 Configurations and critical files (a repeatable script)

```bash
#!/usr/bin/env bash
# backup-config.sh - saves only the irreproducible configurations
set -euo pipefail
DEST="/mnt/backup/rpi-$(date +%F)"     # on a disk/share SEPARATE from the Pi
mkdir -p "$DEST"

# Host security and identity
sudo tar czf "$DEST/host-security.tgz" \
  /etc/ufw /etc/fail2ban /etc/ssh/sshd_config /etc/sysctl.d \
  /etc/ssh/ssh_host_* /root/.ssh/authorized_keys 2>/dev/null || true

# Wazuh (config, rules, certificates)
sudo tar czf "$DEST/wazuh.tgz" /var/ossec/etc /etc/wazuh-indexer /etc/wazuh-dashboard 2>/dev/null || true

# OMV config
sudo cp /etc/openmediavault/config.xml "$DEST/omv-config.xml" 2>/dev/null || true

# Compose + env of all services (adapt the path)
sudo tar czf "$DEST/docker-compose.tgz" /path/to/compose 2>/dev/null || true

echo "Backup in $DEST"
ls -lh "$DEST"
```

### B.2 Docker volumes (the services' data)

```bash
# Backup of a named volume without necessarily stopping the service (better with the container stopped)
docker run --rm -v <volume_name>:/data -v /mnt/backup:/backup alpine \
  tar czf /backup/<volume_name>-$(date +%F).tgz -C /data .
# Repeat for the pihole, wireguard, portainer, cowrie volumes
```

### B.3 Native service exports

```bash
# Pi-hole: Teleporter (from the dashboard: Settings -> Teleporter -> Backup) or CLI
docker exec pihole pihole -a -t                 # creates a teleporter archive

# OMV: native config backup from the web UI (System -> ... -> Config Backup)
```

### B.4 Where to put the backups (3-2-1)

- **Copy 1:** on the NAS itself but on a **different disk** from the boot NVMe (if present).
- **Copy 2:** on an external USB disk / another PC on the LAN (via the NAS's SMB share).
- **Copy 3 (off-site):** encrypted cloud or a disk you keep outside the house. Always encrypt backups that leave the house (they contain keys and passwords): `gpg -c` or `age`.

---

## Part C - Disaster recovery: rebuilding from scratch

Scenario: the NVMe is dead or the system is compromised. Clean rebuild in order.

```
[1] Reinstall the base             [4] Restore the DATA (not the binaries)
    - flash OS on a new NVMe/SD         - OMV config, Docker volumes
    - boot, network, SSH                - Wazuh config+rules, WireGuard keys
        |                                   |
        v                                   v
[2] Recreate the binaries          [5] Restore identity and security
    - scripts/setup.sh all             - SSH host keys, authorized_keys
    - docker compose pull/up           - ufw, fail2ban, sysctl
        |                                   |
        v                                   v
[3] Bring back the services        [6] Verify
    - Wazuh (manual install)           - post-installation checklist
    - containers from the compose      - Runbook 05 (defenses) + Runbook 00 (triage)
```

Concrete steps:

```bash
# [1] Flash Raspberry Pi OS Lite 64-bit on the new NVMe (or boot from the recovery SD),
#     configure network and SSH. See First Setup.

# [2] Clone the repo and run the automation (recreates hardening, Docker, etc.)
git clone <this-repo> && cd RaspberryPi
sudo ./scripts/setup.sh all       # or the single modules: hardening, docker, pihole...

# [3][4] Restore the data on top of the recreated services
sudo tar xzf /mnt/backup/rpi-<date>/host-security.tgz -C /
sudo tar xzf /mnt/backup/rpi-<date>/wazuh.tgz -C /
# Docker volumes:
docker run --rm -v <vol>:/data -v /mnt/backup:/backup alpine \
  sh -c "cd /data && tar xzf /backup/<vol>-<date>.tgz"

# [5] Fix owners/permissions of the Wazuh certificates (see Runbook 03)
sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs
sudo systemctl restart wazuh-indexer wazuh-manager wazuh-dashboard filebeat

# [6] Verify
# run the post-installation checklist and Runbook 05
```

> **Wazuh by hand:** as the project README notes, the Wazuh install on ARM64 is not automated (every step requires verification). In DR, you reinstall Wazuh following its guide and then restore **only** config, rules and certificates from the backup. See [SOC Analyst / Wazuh / installazione](../../SOC%20Analyst/Wazuh/docs/installazione.en.md).

---

## Part D - The DR drill (testing the restore)

A backup only becomes reliable after a test. Run the drill at least once and after every major change:

1. Take a **second NVMe or a MicroSD** (do not touch the production system).
2. Run the full Part C **from the backups only**, without looking at the live system.
3. Time it: it is your **real RTO** for a total rebuild. Note it down.
4. Mark **what was missing** (a config not in the backup, an undocumented step): it is exactly the value of the drill. Update `backup-config.sh` accordingly.
5. Verify the result with [Runbook 05](verifica-difese-attive.en.md).

> A drill that discovers "I had forgotten the WireGuard keys in the backup" just saved you from a real disaster. It is science applied to your own lab: you test the hypothesis ("I can restore") instead of assuming it.

---

## Prevention / cadence

- **Automate** `backup-config.sh` with a weekly cron + volume export with the container stopped (a night window).
- **Verify the integrity** of the backups periodically (`tar tzf` to list without extracting; a corrupted archive is useless).
- **Encrypt** the off-site backups: they contain keys and passwords.
- **Repeat the DR drill** at least once a year and after every architectural change.
- Keep **the repo (with `setup.sh`) and the data backups separate**: the first is public and recreates the binaries, the latter are private and encrypted.

---

## Links

- Clean reinstall after compromise -> [Runbook 06: post-downtime integrity](integrita-post-downtime.en.md)
- NVMe recovery / boot from SD -> [Runbook 01: lost access and boot](accesso-perso-e-boot.en.md)
- Restoring single containers/volumes -> [Runbook 04: VPN and containers](vpn-e-container-recovery.en.md)
- Post-restore verification -> [Runbook 05: verifying active defenses](verifica-difese-attive.en.md)
- Reference initial setup -> [First Setup](../../First%20Setup/)
