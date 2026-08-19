>  [Italiano](troubleshooting.md) |  **English**

# Troubleshooting - NAS / OpenMediaVault: real problems and solutions

> Typical problems of OpenMediaVault 7 on Raspberry Pi: disk not detected by the UI, unreachable web UI, SMB/NFS shares that won't mount, the layered permission model, and the classic config-regeneration trap. For operational disk-space exhaustion see [Incident Recovery / resources and credentials](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.en.md).

---

## Problem 1: OMV overwrites my config file edits

**Symptom:** you manually edit a file in `/etc` (e.g. `sshd_config`, `smb.conf`, `exports`) and after a change from the web UI - or a reboot - the edit disappears.

**Cause:** it is OMV's fundamental behavior, not a bug. OMV keeps the **truth in a database** (`/etc/openmediavault/config.xml`) and **regenerates** the `/etc` files from templates via `omv-salt`. Any manual edit to the generated files is overwritten on the first regeneration.

**Solution:** configure **from the OMV web UI** where possible (the settings go into the database and survive). If you must customize beyond what the UI exposes, use the "Extra options" fields present in many OMV sections, or the documented overrides. To apply/regenerate manually:

```bash
# Regenerate a specific service from the database settings
sudo omv-salt deploy run <service>     # e.g. samba, ssh, nfs
# Read what is in the database (the real source of truth)
sudo omv-confdbadm read conf.service.smb
```

---

## Problem 2: The NVMe (or a disk) does not appear in the OMV UI

**Symptom:** the disk exists (`lsblk` shows it) but OMV does not list it in Storage -> Disks, or won't let you format it.

**Cause:** almost always the disk has **previous partition/filesystem signatures** that confuse OMV, or it is already mounted/in use.

**Solution:**

```bash
# Check what the kernel sees
lsblk -f /dev/nvme0n1

# Show and then remove the residual signatures (WARNING: destructive for the data on the disk)
sudo wipefs /dev/nvme0n1
sudo wipefs -a /dev/nvme0n1     # removes the partition table and filesystem magic bytes
```

> **CRITICAL:** never run `wipefs` on the disk you boot from. Always check with `lsblk` which is the system `mmcblk0`/`nvme0n1` before proceeding. If the NVMe does not appear at all, not even in `lsblk`, the problem is upstream: see [First Setup / troubleshooting, Problem 1](../../First%20Setup/docs/troubleshooting.en.md).

---

## Problem 3: The OMV web UI is unreachable (port 80)

**Symptom:** `http://192.168.0.102` won't open, timeout or "connection refused".

**Cause:** OMV's web service (nginx, `openmediavault-webgui`) is stopped, or another service has taken port 80.

**Solution:**

```bash
# Is OMV's web frontend up?
sudo systemctl status openmediavault-engined nginx
sudo systemctl restart openmediavault-engined nginx

# Who holds port 80?
sudo ss -tulnp | grep :80
# In the lab, Pi-hole runs on a dedicated MacVLAN IP (192.168.0.250), so it does NOT conflict
# with the host's port 80. If you see a conflict, it is another service to move.

# Emergency reset of the web configuration (admin user/password)
sudo omv-firstaid     # interactive menu -> restore web UI access
```

---

## Problem 4: The SMB share won't open from Windows

**Symptom:** from Windows, `\\192.168.0.102\share` gives a credentials error or "unreachable", even though the credentials are correct.

**Cause:** typically one of these: Windows **cached old credentials**, the SMB service is not active, the user does not have **privileges** on the shared folder, or the client is attempting SMB1 (disabled for security).

**Solution:**

```bash
# On the Pi: is the Samba service active and does the share exist?
sudo systemctl status smbd
sudo smbclient -L localhost -U <user>     # lists the shares seen by the server

# On Windows: clear the cached credentials (the #1 cause of false "access denied")
#   net use * /delete
#   Credential Manager -> remove the entries for 192.168.0.102
```

OMV-side checklist:
- The user exists in OMV (Users) and has an SMB password set.
- The shared folder has the correct **privileges** for that user (Shared Folders -> Privileges: Read/Write).
- In Services -> SMB/CIFS the share is enabled.
- If an old client requires SMB1: **do not re-enable it**; update the client. SMB1 is insecure (EternalBlue).

---

## Problem 5: The NFS mount fails from Linux

**Symptom:** `mount -t nfs 192.168.0.102:/export /mnt` gives "access denied" or "permission denied".

**Cause:** the client is not among the authorized IPs in the export, or there is a permission-squashing problem (UID/GID).

**Solution:**

```bash
# On the Pi: which exports are published, and to whom?
sudo exportfs -v
showmount -e 192.168.0.102

# On the client: the IP must fall within the range authorized in the OMV export
sudo mount -t nfs 192.168.0.102:/export/share /mnt -o vers=4
```

OMV-side checklist (Services -> NFS):
- The export exists and lists the right **client/subnet** (e.g. `192.168.0.0/24`), not a single wrong IP.
- The shared folder permissions allow access to the UID that mounts.
- Prefer `root_squash` (secure default): it maps the client's root to `nobody`. Avoid `no_root_squash` unless strictly necessary (it is a privilege escalation vector).

---

## Problem 6: Permission confusion (OMV's three-layer model)

**Symptom:** a user can see but not write (or vice versa) inconsistently across SMB, NFS and SSH.

**Cause:** OMV applies permissions on **three levels** that add up, and the most restrictive wins: (1) filesystem POSIX/ACL permissions, (2) **shared folder** permissions, (3) **per-service privileges** (the SMB/NFS-specific ACLs). A user with Read/Write at the SMB level but with the shared folder in read-only stays read-only.

**Solution:** check in order, from the filesystem to the service.

```bash
# Level 1: real POSIX/ACL permissions on the directory
getfacl /srv/dev-disk-by-*/share

# Levels 2 and 3 are checked from the web UI:
#   Storage -> Shared Folders -> (folder) -> Permissions / ACL
#   Services -> SMB or NFS -> (share) -> Privileges
```

Rule of thumb: define the permissions in **one place** (the Shared Folder privileges) and leave the other levels permissive but consistent, to avoid going mad debugging intersections.

---

## Problem 7: Plex is unreachable or stutters

**Symptom:** Plex does not appear on the network, asks for a "claim", or playback stutters.

**Cause:** the initial claim token is missing, or the Pi is **transcoding** (a very heavy operation for the ARM CPU).

**Solution:**
- On first startup, associate the server with the claim token from `https://plex.tv/claim` (it expires in 4 minutes: generate a fresh one).
- Force **Direct Play/Direct Stream** and avoid transcoding: the Pi 5 does not have a GPU suited to hardware transcoding of multiple streams. Prepare the media in formats already compatible with the clients.
- Check resources during playback: `docker stats plex` (if in a container) or `top`.

---

## Problem 8: An update risks breaking OMV

**Symptom:** after an aggressive update, OMV services won't restart or the UI gives errors.

**Cause:** OMV manages and "pins" some packages; a major version upgrade done by hand can misalign the components.

**Solution:** update from the **OMV web UI** (System -> Update Management) or with the OMV tools, not with arbitrary Debian release upgrades. For ordinary system updates:

```bash
sudo apt update && sudo apt upgrade -y     # ordinary security updates
# For OMV major releases use the official omv-release-upgrade procedure, not by hand
```

Before any major update, back up the config (System -> ... -> Config Backup) and include it in the [Backup Runbook 08](../../Incident%20Recovery%20%26%20Resilience/docs/backup-e-disaster-recovery.en.md).

---

## Useful verification commands

```bash
# Status of the core NAS services
sudo systemctl status openmediavault-engined smbd nfs-kernel-server

# Disk health (SMART)
sudo smartctl -H /dev/nvme0n1
sudo smartctl -a /dev/nvme0n1 | grep -Ei "temperature|percentage used|media errors"

# What is mounted and with which options
findmnt -t ext4,nfs4,cifs

# Read the real config of a service from the OMV database
sudo omv-confdbadm read conf.service.smb
```

---

## Links

- Full disk / exhausted resources (operational side) -> [Incident Recovery / resources and credentials](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.en.md)
- Disk preparation and cleanup -> [preparazione-nvme](preparazione-nvme.en.md)
- SMB/NFS shares in detail -> [configurazione-omv](configurazione-omv.en.md)
- OMV configuration backup -> [Incident Recovery / backup and disaster recovery](../../Incident%20Recovery%20%26%20Resilience/docs/backup-e-disaster-recovery.en.md)
