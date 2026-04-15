>  [Italiano](quick-reference.md) |  **English**

# Quick Reference Card

Quick reference table for daily operations and troubleshooting.

---

## Addresses and Ports

| Service | IP | Port | Protocol | Access |
|---|---|---|---|---|
| Raspberry Pi (host) | `192.168.0.102` | 22/TCP | SSH | LAN only, Ed25519 key |
| OpenMediaVault | `192.168.0.102` | 80/TCP | HTTP | LAN only |
| Portainer | `192.168.0.102` | 9443/TCP | HTTPS | LAN only |
| Wazuh Dashboard | `192.168.0.102` | 443/TCP | HTTPS | LAN only |
| Wazuh Indexer API | `192.168.0.102` | 9200/TCP | HTTPS | LAN only |
| Wazuh Manager (events) | `192.168.0.102` | 1514/TCP | Wazuh protocol | LAN only (agent) |
| Wazuh Manager (registration) | `192.168.0.102` | 1515/TCP | Wazuh protocol | LAN only (agent) |
| Pi-hole | `192.168.0.250` | 53/UDP+TCP | DNS | Entire LAN |
| Pi-hole Dashboard | `192.168.0.250` | 80/TCP | HTTP | LAN only |
| WireGuard VPN | `192.168.0.102` | 51820/UDP | WireGuard | Internet (port forward) |
| WireGuard Web UI | `192.168.0.102` | 51821/TCP | HTTP | LAN only |
| Cowrie Honeypot | `192.168.0.102` | 2222/TCP | SSH (fake) | Internet (port forward) |
| Router gateway | `192.168.0.1` | 80/TCP | HTTP | LAN only |

---

## Default Credentials (change on first access)

| Service | Username | Password | Notes |
|---|---|---|---|
| SSH | `pi` | (Ed25519 key) | Password disabled |
| OpenMediaVault | `admin` | `openmediavault` | Change immediately |
| Portainer | (created on first access) | (created on first access) | Min 12 characters |
| Wazuh Dashboard | `admin` | `admin` | Change with `wazuh-passwords-tool.sh` |
| WireGuard Web UI | - | (set in docker-compose) | `PASSWORD` variable |
| Pi-hole Dashboard | - | (set in docker-compose) | `WEBPASSWORD` variable |

---

## Emergency Commands

```bash
# === SERVICE STATUS ===
sudo systemctl status docker wazuh-manager wazuh-indexer wazuh-dashboard
docker ps -a                        # Active and stopped containers
sudo ufw status verbose             # Active firewall rules
sudo fail2ban-client status sshd    # Banned IPs

# === RESTART SERVICES ===
sudo systemctl restart docker       # Restart Docker (restarts all containers)
sudo systemctl restart wazuh-manager wazuh-indexer wazuh-dashboard
docker restart portainer pihole wireguard cowrie   # Individual containers

# === REAL-TIME LOGS ===
docker logs -f cowrie --tail 50     # Cowrie logs (honeypot)
docker logs -f pihole --tail 50     # Pi-hole logs
sudo tail -f /var/log/auth.log      # SSH attempts
sudo tail -f /var/log/ufw.log       # Packets blocked/allowed by firewall
sudo tail -f /var/ossec/logs/alerts/alerts.json   # Wazuh alerts in real time

# === SSH LOCKOUT RECOVERY ===
# If you locked yourself out (bad UFW rule or lost SSH key):
# 1. Connect HDMI monitor + USB keyboard to the Pi
# 2. Local login with username/password
# 3. sudo ufw disable                # Temporarily disable firewall
# 4. sudo ufw allow ssh              # Re-open SSH
# 5. sudo ufw enable                 # Re-enable
# Or: reflash the MicroSD and use recovery boot

# === DISK SPACE CLEANUP ===
docker system df                    # Show space used by Docker
docker system prune -a              # WARNING: removes everything not in use
sudo journalctl --vacuum-size=100M  # Limit systemd logs to 100MB
```
