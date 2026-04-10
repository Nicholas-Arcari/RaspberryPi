# Quick Reference Card

Tabella di riferimento rapido per operazioni quotidiane e troubleshooting.

---

## Indirizzi e porte

| Servizio | IP | Porta | Protocollo | Accesso |
|---|---|---|---|---|
| Raspberry Pi (host) | `192.168.0.102` | 22/TCP | SSH | Solo LAN, chiave Ed25519 |
| OpenMediaVault | `192.168.0.102` | 80/TCP | HTTP | Solo LAN |
| Portainer | `192.168.0.102` | 9443/TCP | HTTPS | Solo LAN |
| Wazuh Dashboard | `192.168.0.102` | 443/TCP | HTTPS | Solo LAN |
| Wazuh Indexer API | `192.168.0.102` | 9200/TCP | HTTPS | Solo LAN |
| Wazuh Manager (eventi) | `192.168.0.102` | 1514/TCP | Wazuh protocol | Solo LAN (agent) |
| Wazuh Manager (registrazione) | `192.168.0.102` | 1515/TCP | Wazuh protocol | Solo LAN (agent) |
| Pi-hole | `192.168.0.250` | 53/UDP+TCP | DNS | Tutta la LAN |
| Pi-hole Dashboard | `192.168.0.250` | 80/TCP | HTTP | Solo LAN |
| WireGuard VPN | `192.168.0.102` | 51820/UDP | WireGuard | Internet (port forward) |
| WireGuard Web UI | `192.168.0.102` | 51821/TCP | HTTP | Solo LAN |
| Cowrie Honeypot | `192.168.0.102` | 2222/TCP | SSH (finto) | Internet (port forward) |
| Router gateway | `192.168.0.1` | 80/TCP | HTTP | Solo LAN |

---

## Credenziali default (da cambiare al primo accesso)

| Servizio | Username | Password | Note |
|---|---|---|---|
| SSH | `pi` | (chiave Ed25519) | Password disabilitata |
| OpenMediaVault | `admin` | `openmediavault` | Cambiare immediatamente |
| Portainer | (creato al primo accesso) | (creato al primo accesso) | Min 12 caratteri |
| Wazuh Dashboard | `admin` | `admin` | Cambiare con `wazuh-passwords-tool.sh` |
| WireGuard Web UI | - | (impostata nel docker-compose) | Variabile `PASSWORD` |
| Pi-hole Dashboard | - | (impostata nel docker-compose) | Variabile `WEBPASSWORD` |

---

## Comandi di emergenza

```bash
# === STATO DEI SERVIZI ===
sudo systemctl status docker wazuh-manager wazuh-indexer wazuh-dashboard
docker ps -a                        # Container attivi e fermi
sudo ufw status verbose             # Regole firewall attive
sudo fail2ban-client status sshd    # IP bannati

# === RIAVVIO SERVIZI ===
sudo systemctl restart docker       # Riavvia Docker (riavvia tutti i container)
sudo systemctl restart wazuh-manager wazuh-indexer wazuh-dashboard
docker restart portainer pihole wireguard cowrie   # Container singoli

# === LOG IN TEMPO REALE ===
docker logs -f cowrie --tail 50     # Log Cowrie (honeypot)
docker logs -f pihole --tail 50     # Log Pi-hole
sudo tail -f /var/log/auth.log      # Tentativi SSH
sudo tail -f /var/log/ufw.log       # Pacchetti bloccati/permessi dal firewall
sudo tail -f /var/ossec/logs/alerts/alerts.json   # Alert Wazuh in tempo reale

# === RECUPERO DA BLOCCO SSH ===
# Se ti sei chiuso fuori (regola UFW sbagliata o chiave SSH persa):
# 1. Collega monitor HDMI + tastiera USB al Pi
# 2. Login locale con username/password
# 3. sudo ufw disable                # Disabilita firewall temporaneamente
# 4. sudo ufw allow ssh              # Riapri SSH
# 5. sudo ufw enable                 # Riabilita
# Oppure: riflasha la MicroSD e usa il boot di recovery

# === PULIZIA SPAZIO DISCO ===
docker system df                    # Mostra spazio usato da Docker
docker system prune -a              # ATTENZIONE: rimuove tutto cio' che non e' in uso
sudo journalctl --vacuum-size=100M  # Limita i log di systemd a 100MB
```
