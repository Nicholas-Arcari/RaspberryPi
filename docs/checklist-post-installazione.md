>  [English](checklist-post-installazione.en.md) |  **Italiano**

# Checklist post-installazione

Dopo aver completato il setup di tutti i componenti, esegui questa verifica per confermare che tutto funzioni correttamente. Ogni check ha un comando e il risultato atteso.

---

## Infrastruttura base

```bash
# [ ] Sistema aggiornato
sudo apt update && apt list --upgradable
# Risultato atteso: nessun pacchetto da aggiornare (o solo pochi non-security)

# [ ] Boot da NVMe (se configurato)
lsblk | grep -E "nvme|mmcblk"
# Risultato atteso: la partizione root (/) è su nvme0n1p2, non su mmcblk0

# [ ] EEPROM aggiornato
sudo rpi-eeprom-update
# Risultato atteso: "BOOTLOADER: up to date"
```

---

## Sicurezza

```bash
# [ ] SSH accetta solo chiavi pubbliche
ssh -o PasswordAuthentication=yes pi@localhost 2>&1 | grep -i "permission denied"
# Risultato atteso: "Permission denied" (password rifiutata)

# [ ] UFW attivo con policy corrette
sudo ufw status verbose | head -5
# Risultato atteso: "Status: active", "Default: deny (incoming), allow (outgoing)"

# [ ] Fail2ban attivo sulla jail SSH
sudo fail2ban-client status sshd
# Risultato atteso: "Filter" e "Actions" presenti, nessun errore

# [ ] Sysctl hardening applicato
sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space
# Risultato atteso: tcp_syncookies = 1, randomize_va_space = 2
```

---

## Container

```bash
# [ ] Docker attivo
docker version --format '{{.Server.Version}}'
# Risultato atteso: versione Docker (es. 20.10.x)

# [ ] Tutti i container in esecuzione
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# Risultato atteso: portainer, pihole, wireguard, cowrie tutti "Up"

# [ ] Portainer raggiungibile
curl -sk https://localhost:9443 | head -1
# Risultato atteso: HTML della pagina Portainer (non "connection refused")

# [ ] Pi-hole risponde alle query DNS
dig @192.168.0.250 google.com +short
# Risultato atteso: un indirizzo IP (es. 142.250.x.x)

# [ ] Pi-hole blocca i tracker
dig @192.168.0.250 ads.doubleclick.net +short
# Risultato atteso: 0.0.0.0 (bloccato)
```

---

## SIEM e Monitoraggio

```bash
# [ ] Wazuh Manager attivo
sudo systemctl is-active wazuh-manager
# Risultato atteso: "active"

# [ ] Wazuh Indexer attivo e raggiungibile
curl -sk https://localhost:9200 -u admin:admin | python3 -m json.tool | head -5
# Risultato atteso: JSON con nome del cluster e versione OpenSearch

# [ ] Wazuh Dashboard raggiungibile
curl -sk https://localhost:443 | head -1
# Risultato atteso: HTML della pagina di login

# [ ] Filebeat invia dati all'Indexer
sudo filebeat test output
# Risultato atteso: "elasticsearch: https://127.0.0.1:9200... OK"

# [ ] Agent locale connesso
sudo /var/ossec/bin/agent_control -l
# Risultato atteso: agent ID 000 o 001 con stato "Active"
```

---

## Honeypot

```bash
# [ ] Cowrie accetta connessioni
ssh -o StrictHostKeyChecking=no root@localhost -p 2222
# Risultato atteso: prompt di login (accetta password comuni come "12345")
# Digita "exit" per uscire

# [ ] I log Cowrie vengono generati
docker exec cowrie tail -1 /home/cowrie/cowrie-git/var/log/cowrie/cowrie.json
# Risultato atteso: riga JSON con l'ultimo evento
```

---

## VPN

```bash
# [ ] WireGuard in ascolto
ss -ulnp | grep 51820
# Risultato atteso: riga con 0.0.0.0:51820 (LISTEN)

# [ ] Web UI raggiungibile
curl -s http://localhost:51821 | head -1
# Risultato atteso: HTML della pagina wg-easy

# [ ] Tunnel funzionante (da un client connesso)
# Sul client VPN: ping 192.168.0.102
# Risultato atteso: risposta dal Pi
```

---

## VLAN (se configurata)

```bash
# [ ] Interfaccia VLAN attiva
ip link show end0.150
# Risultato atteso: stato UP

# [ ] Rete Docker IPVLAN presente
docker network inspect ipvlan_150 --format '{{.IPAM.Config}}'
# Risultato atteso: [{192.168.150.0/24 192.168.150.1 map[]}]
```

> **Frequenza consigliata:** Esegui questa checklist dopo ogni modifica significativa (aggiornamento OS, aggiunta container, modifica regole UFW) e come minimo una volta al mese. Puoi automatizzarla con lo script `scripts/setup.sh verify`.
