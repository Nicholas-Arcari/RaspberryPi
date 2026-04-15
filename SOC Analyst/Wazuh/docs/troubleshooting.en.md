>  [Italiano](troubleshooting.md) |  **English**

# Wazuh Troubleshooting and Maintenance

## Issues Encountered and Solutions

### 1. Automatic Script "Uncompatible system"

**Problem:** The `wazuh-install.sh` script blocked the installation with an "Uncompatible system" error on Raspberry Pi OS.

**Cause:** The script checks `/etc/os-release` and the list of supported systems does not include Raspberry Pi OS (even though it is Debian-based).

**Solution:** Abandoned the script in favor of manual installation via `apt` with the repository forced to `arch=arm64`.

### 2. GPG "Permission denied"

**Problem:** The command `curl ... | gpg ...` returned "Permission denied."

**Cause:** The pipe `|` executes the second command with the current user's permissions (not root). `gpg` was trying to write to `/usr/share/keyrings/` which requires root privileges.

**Solution:** `curl ... | sudo gpg ...` - the `sudo` goes on the second command of the pipe, not the first.

### 3. Dashboard "No template found"

**Problem:** The Dashboard was reachable but displayed a persistent red error and no data.

**Cause:** Two possibilities:
- Filebeat not installed or not started
- ILM enabled, which created indices with the wrong naming pattern (`filebeat-7.x` instead of `wazuh-alerts-*`)

**Solution:** Installed Filebeat, disabled ILM (`setup.ilm.enabled: false`), and forced the correct template loading with `filebeat setup --index-management`.

### 4. Services Won't Start - "Permission denied" on Certificates

**Problem:** `systemctl start wazuh-indexer` failed. Logs showed "Permission denied" on the `.pem` files.

**Cause:** The certificates had been copied with the current user's permissions. The `wazuh-indexer` service runs as the `wazuh-indexer` user and could not read files owned by `root`.

**Solution:** Correct `chown` for each component and restrictive permissions (`chmod 400` on files, `chmod 500` on directories).

---

## Useful Maintenance Commands

```bash
# Status of all Wazuh services
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard filebeat

# Test Filebeat -> Indexer connection
sudo filebeat test output

# Manager log (for debugging rules and decoders)
sudo tail -f /var/ossec/logs/ossec.log

# Indexer log (for indexing issues)
sudo journalctl -u wazuh-indexer -f

# Test rules in real time
sudo /var/ossec/bin/wazuh-logtest

# Reset admin password (if necessary)
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
```
